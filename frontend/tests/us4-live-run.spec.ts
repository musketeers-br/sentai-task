import { writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { canonicalFlow, EVIDENCE_DIR, PASSWORD, seedFlow, signIn, USER } from './support';

// spec.md User Story 4 — Live Run and Per-Step Control (Q6, Q7), against real runs.
// v1 facts (plan-us4-live-run.md): integrity-check takes ~51 s here; a run's credential lasts
// 60 s (spec 004 E-1), so a step still being polled after that fails with the platform's 401.

const ic = (id: string, taskName: string, namespace: string, databaseDirectory: string) => ({
	id,
	type: 'integrity-check',
	taskName,
	namespace,
	databaseDirectory,
	runAsUser: 'irisadm',
	wqmCategory: 'Default',
	timeoutMinutes: 30
});

async function dispatchFromUi(page: Page) {
	await page.getByRole('button', { name: 'Run now' }).click();
	await page.getByLabel(`Password for ${USER}`).fill(PASSWORD);
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
	await expect(page.getByTestId('run-state')).toBeVisible();
}

const chip = (page: Page, stepId: string) =>
	page.locator(`.svelte-flow__node[data-id="${stepId}"]`).getByTestId('state-chip');

test('Q6/Q7 — live states per step; cancelling one step leaves its siblings running', async ({ page, request }) => {
	// #01 → #05 → #06 run back to back (~50 s each) now that runs outlive 60 s (E-1).
	test.setTimeout(300_000);
	// 01–04 in parallel; 05 after 01; 06 after 05 — so one run can show 4+ states at once.
	const id = await seedFlow(request, {
		name: `Q6 live run ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			ic('01', 'Integrity check — USER', 'USER', '/usr/irissys/mgr/user/'),
			ic('02', 'Integrity check — IRISAPP', 'IRISAPP', '/data/IRISAPP_DATA/'),
			ic('03', 'Integrity check — USER (2)', 'USER', '/usr/irissys/mgr/user/'),
			ic('04', 'Integrity check — IRISAPP (2)', 'IRISAPP', '/data/IRISAPP_DATA/'),
			ic('05', 'Integrity check — after #01', 'USER', '/usr/irissys/mgr/user/'),
			ic('06', 'Integrity check — after #05', 'IRISAPP', '/data/IRISAPP_DATA/')
		],
		edges: [
			{ source: '01', target: '05' },
			{ source: '05', target: '06' }
		],
		joins: [],
		canvasGeometry: {
			nodes: {
				'01': { x: 0, y: 0 },
				'02': { x: 0, y: 190 },
				'03': { x: 0, y: 380 },
				'04': { x: 0, y: 570 },
				'05': { x: 330, y: 0 },
				'06': { x: 660, y: 0 }
			}
		}
	});
	await signIn(page, `?flow=${id}`);
	await dispatchFromUi(page);

	const log: Array<{ timestamp: string; event: string; detail: object }> = [];
	const record = (event: string, detail: object) => log.push({ timestamp: new Date().toISOString(), event, detail });

	// FR-021/FR-022: every step has a state chip from the start; roots run, dependants queue.
	await expect(page.getByTestId('run-state')).toContainText('RUN IN PROGRESS');
	for (const s of ['01', '02', '03', '04']) await expect(chip(page, s)).toHaveText('RUNNING');
	await expect(chip(page, '05')).toHaveText('QUEUED');
	await expect(page.getByTestId('count-line')).toHaveText('0 completed · 0 failed · 4 running · 2 queued');
	await expect(page.getByTestId('run-guid')).toHaveText(new URL(page.url()).searchParams.get('run')!);
	record('dispatched', { run: new URL(page.url()).searchParams.get('run') });

	// Scenario 3 / FR-030: cancel #04 only; siblings keep running.
	const cancelAt = Date.now();
	await page.locator('.svelte-flow__node[data-id="04"]').getByRole('button', { name: 'Cancel' }).click();
	await expect(chip(page, '04')).toHaveText('CANCELLED');
	record('step #04 cancel → cancelled', { elapsedMs: Date.now() - cancelAt });
	expect(Date.now() - cancelAt, 'NFR-001: visible within 2 s').toBeLessThan(2000);
	for (const s of ['01', '02', '03']) await expect(chip(page, s)).toHaveText('RUNNING');
	record('siblings #01 #02 #03 still running', {});

	// Q6: at least four of the six states live at once — completed, cancelled, running, queued.
	await expect(chip(page, '05')).toHaveText('RUNNING', { timeout: 90_000 });
	const states = new Set(await page.getByTestId('state-chip').allTextContents());
	record('states live together', { states: [...states] });
	expect(states.size).toBeGreaterThanOrEqual(4);
	await expect(page.getByTestId('count-line')).toHaveText('3 completed · 0 failed · 1 running · 1 queued · 1 cancelled');
	await page.screenshot({ path: `${EVIDENCE_DIR}/q6-live-run.png` });

	// The run ends; any failure reason is shown verbatim, and the six-state key is always there.
	await expect(page.getByTestId('run-state')).not.toContainText('IN PROGRESS', { timeout: 180_000 });
	// Nothing failed and #04 was cancelled: the run must not claim success (Constitution IV).
	await expect(page.getByTestId('run-state')).toContainText('RUN CANCELLED');
	record('run terminal', { state: await page.getByTestId('run-state').textContent() });
	for (const reason of await page.getByTestId('failure-reason').locator('pre').allTextContents()) {
		expect(reason.trim().length).toBeGreaterThan(0);
	}
	await expect(page.getByLabel('Run details').locator('.key li')).toHaveText([
		'queued',
		'running',
		'paused',
		'completed',
		'failed',
		'cancelled'
	]);

	writeFileSync(
		`${EVIDENCE_DIR}/q7-step-control.json`,
		JSON.stringify({ evidence_id: 'q7-step-control', captured_at: new Date().toISOString(), entries: log }, null, 2)
	);
});

test('E-1 — the demo wave (3 in parallel → join → 2 in sequence) runs past 60 s to completed', async ({ page, request }) => {
	test.setTimeout(300_000);
	const id = await seedFlow(request, {
		name: `E-1 demo wave ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			ic('01', 'Integrity check — USER', 'USER', '/usr/irissys/mgr/user/'),
			ic('02', 'Integrity check — IRISAPP', 'IRISAPP', '/data/IRISAPP_DATA/'),
			ic('03', 'Integrity check — USER (2)', 'USER', '/usr/irissys/mgr/user/'),
			ic('04', 'Integrity check — after the join', 'IRISAPP', '/data/IRISAPP_DATA/'),
			ic('05', 'Integrity check — final', 'USER', '/usr/irissys/mgr/user/')
		],
		edges: [
			{ source: '01', target: '04' },
			{ source: '02', target: '04' },
			{ source: '03', target: '04' },
			{ source: '04', target: '05' }
		],
		joins: [{ target: '04', policy: 'ALL_MUST_SUCCEED' }],
		canvasGeometry: {
			nodes: {
				'01': { x: 0, y: 0 },
				'02': { x: 0, y: 200 },
				'03': { x: 0, y: 400 },
				'04': { x: 340, y: 200 },
				'05': { x: 680, y: 200 }
			}
		}
	});
	await signIn(page, `?flow=${id}`);
	await dispatchFromUi(page);

	// Before the fix, every step still being polled after the run's first 60 s failed with 401.
	await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED', { timeout: 280_000 });
	await expect(page.getByTestId('count-line')).toHaveText('5 completed · 0 failed · 0 running · 0 queued');
	await expect(page.getByTestId('failure-reason')).toHaveCount(0);
	const [minutes, seconds] = (await page.getByTestId('elapsed-clock').textContent())!.split(':').slice(1).map(Number);
	expect(minutes * 60 + seconds, 'the run outlived the 60 s access token').toBeGreaterThan(60);
	await page.screenshot({ path: `${EVIDENCE_DIR}/e1-demo-wave-completed.png` });
});

test('Q7 — Cancel wave asks for confirmation naming the run, then stops it', async ({ page, request }) => {
	const id = await seedFlow(request, {
		name: `Q7 cancel wave ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			ic('01', 'Integrity check — USER', 'USER', '/usr/irissys/mgr/user/'),
			ic('02', 'Integrity check — after #01', 'IRISAPP', '/data/IRISAPP_DATA/')
		],
		edges: [{ source: '01', target: '02' }],
		joins: []
	});
	await signIn(page, `?flow=${id}`);
	await dispatchFromUi(page);
	const runGuid = new URL(page.url()).searchParams.get('run')!;

	await page.getByRole('button', { name: 'Cancel wave' }).click();
	const confirm = page.getByRole('dialog', { name: 'Cancel wave?' });
	await expect(confirm).toContainText(runGuid.split('-').slice(0, 4).join('-'));
	await confirm.getByRole('button', { name: 'Cancel wave' }).click();

	await expect(page.getByTestId('run-state')).toContainText('RUN CANCELLED', { timeout: 10_000 });
	await expect(chip(page, '02')).toHaveText('CANCELLED');
	await expect(page.getByRole('button', { name: 'Cancel wave' })).toBeDisabled();
});

test('Dispatch is refused for a flow with steps unsupported in v1, naming them on the canvas', async ({ page, request }) => {
	const id = await seedFlow(request, canonicalFlow(`Dispatch refused ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	await page.getByRole('button', { name: 'Run now' }).click();
	await page.getByLabel(`Password for ${USER}`).fill(PASSWORD);
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();

	await expect(page.getByRole('dialog').getByRole('alert')).toContainText('Not dispatched');
	await page.getByRole('dialog').getByRole('button', { name: 'Cancel' }).click();
	// Spec 005: switch-journal (#05) is available, so only #04 is refused.
	await expect(page.getByTestId('status-errors')).toHaveText('1 error blocks scheduling (#04)');
	await expect(page.getByTestId('run-state')).toHaveCount(0);
});
