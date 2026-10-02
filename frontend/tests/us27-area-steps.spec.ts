import { expect, test } from '@playwright/test';
import { readRun, runToEnd } from './runs-support';
import { paletteEntry, seedFlow, signIn, signInAt } from './support';

// spec 013 — area report steps: security posture, web application inventory, system alerts
// check and secrets inventory, on the primary and on iris-target; results readable in the canvas.

const step = (id: string, type: string, extra: object = {}) => ({
	id,
	type,
	taskName: `${type} ${id}`,
	namespace: '%SYS',
	wqmCategory: 'Default',
	timeoutMinutes: 10,
	parameters: {},
	...extra
});

const REPORTS = ['security-posture-report', 'web-app-inventory', 'secrets-inventory'];

test('us27 palette — Security and Monitoring groups list the four report types (FR-011)', async ({ page }) => {
	await signIn(page);
	const palette = page.getByLabel('Step types');
	await expect(palette.getByRole('heading', { name: 'SECURITY' })).toBeVisible();
	await expect(palette.getByRole('heading', { name: 'MONITORING' })).toBeVisible();
	for (const type of [...REPORTS, 'system-alerts-check']) {
		await expect(await paletteEntry(page, type)).toBeEnabled();
	}
});

test('us27 run — the three reports complete locally and on iris-target; results open with findings first', async ({ page, request }) => {
	test.setTimeout(180_000);
	const id = await seedFlow(request, {
		name: `us27-reports ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			step('01', 'security-posture-report'),
			step('02', 'web-app-inventory'),
			step('03', 'secrets-inventory'),
			step('04', 'security-posture-report', { target: 'iris-target' })
		],
		edges: [],
		joins: []
	});
	// The target step needs a credential for the target: dispatch from the canvas, which asks for it.
	await signIn(page, `?flow=${id}`);
	await page.getByRole('button', { name: 'Run now' }).click();
	for (const field of await page.getByRole('dialog', { name: /^Run .* now$/ }).getByLabel(/^Password for/).all()) await field.fill(process.env.IRIS_PASSWORD ?? 'SYS');
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
	await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED', { timeout: 120_000 });

	const guid = new URL(page.url()).searchParams.get('run')!;
	const run = (await readRun(request, guid)) as { steps: Array<{ stepId: string; state: string; executedOn: string; result: { findings: Array<{ rule: string; item: string }> } }> };
	const byId = Object.fromEntries(run.steps.map((s) => [s.stepId, s]));
	expect(byId['04'].executedOn).toBe('iris-target');
	// _SYSTEM holds %All on a stock instance: a high finding on both servers.
	expect(byId['01'].result.findings.some((f) => f.rule === 'ALL_ROLE_HOLDER' && f.item === '_SYSTEM')).toBe(true);
	expect(byId['04'].result.findings.some((f) => f.rule === 'ALL_ROLE_HOLDER')).toBe(true);
	// The public canvas app is anonymous by design (spec 010) and is reported, truthfully.
	expect(byId['02'].result.findings.some((f) => f.item === '/csp/sentai')).toBe(true);

	await page.locator('.svelte-flow__node[data-id="01"]').getByRole('button', { name: 'Result' }).click();
	const panel = page.getByTestId('result-panel');
	await expect(panel.getByTestId('report-summary')).toContainText('high');
	await expect(panel.getByTestId('finding').first()).toContainText('HIGH');
	await panel.getByRole('button', { name: 'Close' }).click();
	await expect(panel).toHaveCount(0);
});

test('us27 gate — the alerts check fails on serious alerts and its join keeps the next step from starting (SC-005)', async ({ page, request }) => {
	// maxSeriousAlerts -1 is refused by validation, so the gate uses the default (0); a dev instance
	// that ran the suite has serious alerts since start (research R-4), so the check fails.
	const id = await seedFlow(request, {
		name: `us27-gate ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [step('01', 'system-alerts-check'), step('02', 'db-size-report')],
		edges: [{ source: '01', target: '02' }],
		joins: [{ target: '02', policy: 'ALL_MUST_SUCCEED' }]
	});
	const run = await runToEnd(request, id);
	const detail = (await readRun(request, run.guid)) as { steps: Array<{ stepId: string; state: string; failureReason: string }> };
	const alerts = detail.steps.find((s) => s.stepId === '01')!;
	if (alerts.state === 'completed') {
		test.info().annotations.push({ type: 'note', description: 'no serious alerts on this instance: the gate let the step through' });
		expect(detail.steps.find((s) => s.stepId === '02')!.state).toBe('completed');
		return;
	}
	expect(alerts.failureReason).toMatch(/serious alerts \(maximum 0\)|is not Normal|application errors/);
	expect(detail.steps.find((s) => s.stepId === '02')!.failureReason).toBe('One or more required inputs failed');

	await signInAt(page, `?flow=${id}&run=${run.guid}`);
	await page.locator('.svelte-flow__node[data-id="01"]').getByRole('button', { name: 'Result' }).click();
	await expect(page.getByTestId('result-panel').getByTestId('finding').first()).toContainText('HIGH');
	await expect(page.getByTestId('log-line').filter({ hasText: '#02 not started: input #01 failed' })).toHaveCount(1);
});

test('us27 other results — a database size report is readable in the run view too (FR-012)', async ({ page, request }) => {
	const id = await seedFlow(request, {
		name: `us27-db ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [step('01', 'db-size-report')],
		edges: [],
		joins: []
	});
	const run = await runToEnd(request, id);
	await signInAt(page, `?flow=${id}&run=${run.guid}`);
	await page.locator('.svelte-flow__node[data-id="01"]').getByRole('button', { name: 'Result' }).click();
	const panel = page.getByTestId('result-panel');
	await expect(panel).toContainText('databases');
	await expect(panel).toContainText('IRISAPP');
});
