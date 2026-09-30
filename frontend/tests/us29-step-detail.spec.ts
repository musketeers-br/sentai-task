import { writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { readRun, runToEnd } from './runs-support';
import { seedFlow, signInAt, token } from './support';

// Spec 016 US2 (MVP) — one step's execution, in full: selecting a step (node or row) opens its
// account in the rail — state, times, duration, where, as whom, the platform's failure reason
// whole and copyable, the stored result readable and copyable — addressable as ?run=&step=.
// 01 completes with a result, 02 fails with the platform's verbatim reason (and its result),
// 03 is blocked behind 02's join and stays queued (FR-011: nothing invented for a step that
// never ran). Nothing here needs log entries (the stack's backend writes them since spec 012).

const EVIDENCE = '../specs/016-run-log-details/evidence';

test.use({ permissions: ['clipboard-read', 'clipboard-write'] });

const step = (id: string, type: string, parameters: object = {}) => ({
	id,
	type,
	taskName: `${type} ${id}`,
	namespace: 'USER',
	runAsUser: 'irisadm',
	wqmCategory: 'Default',
	timeoutMinutes: 10,
	parameters
});

async function seedAndRun(request: import('@playwright/test').APIRequestContext) {
	const flowId = await seedFlow(request, {
		name: `us29-step-detail ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			step('01', 'db-size-report'),
			step('02', 'storage-headroom-check', { minFreePercent: 100 }),
			step('03', 'storage-headroom-check')
		],
		edges: [{ source: '02', target: '03' }],
		joins: [{ target: '03', policy: 'ALL_MUST_SUCCEED' }]
	});
	const { guid, state } = await runToEnd(request, flowId);
	expect(state, '01 completes, 02 fails, 03 is blocked by the join').toBe('failed');
	return { flowId, guid };
}

const node = (page: Page, id: string) => page.locator(`.svelte-flow__node[data-id="${id}"]`);
const detail = (page: Page) => page.getByTestId('step-detail');

test('us29 — a step\'s full account: facts, whole verbatim reason, result, copy, address', async ({
	page,
	request
}) => {
	test.setTimeout(120_000);
	const { flowId, guid } = await seedAndRun(request);
	const run = (await readRun(request, guid)) as {
		steps: Array<{ stepId: string; state: string; failureReason: string | null; result: unknown }>;
	};
	const byId = Object.fromEntries(run.steps.map((s) => [s.stepId, s]));
	writeFileSync(`${EVIDENCE}/us29-run-read.json`, JSON.stringify(run, null, 2));

	await signInAt(page, `?flow=${flowId}&run=${guid}`);
	await expect(page.getByTestId('run-state')).toContainText('RUN FAILED');

	// --- the completed step: facts and its stored result, readable and copyable (SC-006) -----
	await node(page, '01').click();
	await expect(detail(page)).toBeVisible();
	await expect(detail(page).getByTestId('detail-state')).toContainText('COMPLETED');
	await expect(detail(page).getByTestId('detail-where')).toContainText('on local · as _SYSTEM');
	await expect(detail(page).getByTestId('detail-where')).not.toContainText('—');
	await expect(detail(page).getByTestId('result-panel')).toBeVisible();
	await expect(detail(page).getByTestId('result-panel')).toContainText('sizeMB');
	await detail(page).getByTestId('copy-result').click();
	expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
		JSON.stringify(byId['01'].result, null, 2)
	);

	// --- the failed step: the platform's reason whole and copyable (SC-002, Constitution III) -
	await node(page, '02').click();
	const reason = byId['02'].failureReason!;
	expect(reason.length, 'a long reason, kept whole').toBeGreaterThan(100);
	await expect(detail(page).getByTestId('failure-reason')).toHaveText(reason);
	await detail(page).getByTestId('copy-reason').click();
	expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(reason);

	// --- the address is the selection: reload keeps it, back and Close release it ------------
	expect(new URL(page.url()).searchParams.get('step')).toBe('02');
	await page.reload();
	await expect(detail(page)).toBeVisible();
	await expect(detail(page).getByTestId('failure-reason')).toHaveText(reason);
	// Each selection is a history entry: back steps to 01's selection, then off the detail.
	await page.goBack();
	await expect(detail(page).getByTestId('detail-state')).toContainText('COMPLETED');
	await page.goBack();
	await expect(detail(page)).toBeHidden();
	expect(new URL(page.url()).searchParams.get('step')).toBeNull();
	await node(page, '02').click();
	await detail(page).getByTestId('close-detail').click();
	await expect(detail(page)).toBeHidden();
	expect(new URL(page.url()).searchParams.get('step')).toBeNull();

	// --- a join-blocked step: failed by the join, and still nothing invented (FR-011) -----------
	await node(page, '03').click();
	await expect(detail(page).getByTestId('detail-state')).toContainText('FAILED');
	await expect(detail(page).getByTestId('detail-where')).toHaveText('—');
	await expect(detail(page).getByTestId('detail-started')).toHaveText('—');

	// --- the step list row selects too --------------------------------------------------------
	await page.getByTestId('step-row-01').click();
	await expect(detail(page).getByTestId('detail-state')).toContainText('COMPLETED');

	await page.screenshot({ path: `${EVIDENCE}/us29-step-detail.png`, fullPage: false });
});

test('us29 — a step that has not started shows what is known and invents nothing (FR-011)', async ({
	page,
	request
}) => {
	test.setTimeout(120_000);
	// 02 waits behind a slow integrity check (~50 s): it is queued for the whole window. The plain
	// 60 s token covers it; this test only needs the run live, not finished.
	const flowId = await seedFlow(request, {
		name: `us29-queued ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			{
				id: '01',
				type: 'integrity-check',
				taskName: 'Slow integrity check',
				namespace: 'USER',
				databaseDirectory: '/usr/irissys/mgr/user/',
				runAsUser: 'irisadm',
				wqmCategory: 'Default',
				timeoutMinutes: 30
			},
			step('02', 'db-size-report')
		],
		edges: [{ source: '01', target: '02' }],
		joins: [{ target: '02', policy: 'ALL_MUST_SUCCEED' }]
	});
	const access = await token(request);
	const run = await request.post('/csp/sentai/api/v1/flows/' + flowId + '/dispatch', {
		headers: { Authorization: `Bearer ${access}` },
		data: { confirmations: [] }
	});
	const guid = String((await run.json()).guid);

	await signInAt(page, `?flow=${flowId}&run=${guid}`);
	await expect(page.getByTestId('run-state')).toContainText('RUN IN PROGRESS');
	await node(page, '02').click();
	await expect(detail(page).getByTestId('detail-state')).toContainText('QUEUED');
	await expect(detail(page).getByTestId('detail-where')).toHaveText('—');
	await expect(detail(page).getByTestId('detail-started')).toHaveText('—');
	expect(detail(page).getByTestId('failure-reason')).toBeHidden();

	// Cancel the wave so the slow integrity check does not run on into the next specs (it holds
	// the database's integrity check; us4's would queue behind it). Cancelling is house-normal
	// (us4 cancels a step too); IRIS logs it and the container shows the documented alert.
	await request.post('/csp/sentai/api/v1/runs/' + guid + '/cancel', {
		headers: { Authorization: `Bearer ${access}` },
		data: {}
	});
});
