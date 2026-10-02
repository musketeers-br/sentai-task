import { expect, test, type APIRequestContext } from '@playwright/test';
import { createTestCertificate, deleteFlowWithRuns, deleteTestCertificate } from './iris';
import { readRun, runToEnd } from './runs-support';
import { flowButton, paletteEntry, seedFlow, signIn, signInAt, token } from './support';

// spec 020 — security inventory: certificate expiry check, permissions inventory, OAuth
// inventory, on the primary and on iris-target; results readable in the canvas.

const step = (id: string, type: string, parameters: object = {}, extra: object = {}) => ({
	id,
	type,
	taskName: `${type} ${id}`,
	namespace: '%SYS',
	wqmCategory: 'Default',
	timeoutMinutes: 10,
	parameters,
	...extra
});

type StepRead = { stepId: string; state: string; failureReason: string; executedOn: string; result: Record<string, any> };

async function seed(request: APIRequestContext, name: string, steps: object[]) {
	// Each node at its own place, so each one's Result button can be clicked.
	const nodes = Object.fromEntries((steps as Array<{ id: string }>).map((s, i) => [s.id, { x: 40 + 320 * i, y: 60 }]));
	return seedFlow(request, { name, defaultCategory: 'Default', steps, edges: [], joins: [], canvasGeometry: { nodes } });
}

async function stepsOf(request: APIRequestContext, guid: string): Promise<Record<string, StepRead>> {
	const run = (await readRun(request, guid)) as { steps: StepRead[] };
	return Object.fromEntries(run.steps.map((s) => [s.stepId, s]));
}

test('us29 A — a certificate inside the threshold fails the check; a smaller threshold lets it pass', async ({ page, request }) => {
	test.setTimeout(180_000);
	const alias = `sentai-e2e-020-${Date.now()}`;
	const name = `us29-cert ${Date.now()}`;
	createTestCertificate(alias, 10);
	const id = await seed(request, name, [step('01', 'certificate-expiry-check', { warnDays: 30 }), step('02', 'certificate-expiry-check', { warnDays: 5 })]);
	try {
		const run = await runToEnd(request, id);
		const steps = await stepsOf(request, run.guid);
		expect(steps['01'].state).toBe('failed');
		expect(steps['01'].failureReason).toContain('expired or expiring within 30 days');
		expect(steps['01'].failureReason).toContain(alias);
		expect(steps['01'].result.findings.some((f: { rule: string; item: string }) => f.rule === 'CERT_EXPIRING' && f.item === alias)).toBe(true);
		expect(steps['02'].state).toBe('completed');
		const mine = steps['02'].result.details.credentials.find((c: { alias: string }) => c.alias === alias);
		expect(mine, 'the test certificate is in the (possibly cut) details').toBeTruthy();
		expect(mine.status).toBe('valid');
		expect([9, 10]).toContain(mine.daysLeft);
		expect(JSON.stringify(steps)).not.toMatch(/PRIVATE KEY|PrivateKeyPassword|ClientSecret/);

		await signInAt(page, `?flow=${id}&run=${run.guid}`);
		await page.locator('.svelte-flow__node[data-id="01"]').getByRole('button', { name: 'Result' }).click();
		const panel = page.getByTestId('result-panel');
		await expect(panel.getByTestId('finding').first()).toContainText('CERT_EXPIRING');
		await expect(panel.getByTestId('finding').first()).toContainText(alias);
	} finally {
		deleteTestCertificate(alias);
		deleteFlowWithRuns(id, name);
	}
});

test('us29 B — permissions: counts equal the platform, locally and on iris-target', async ({ page, request }) => {
	test.setTimeout(180_000);
	const name = `us29-perm ${Date.now()}`;
	const id = await seed(request, name, [step('01', 'permissions-inventory'), step('02', 'permissions-inventory', {}, { target: 'iris-target' })]);
	try {
		// The target step needs a credential for the target: dispatch from the canvas, which asks for it.
		await signIn(page, `?flow=${id}`);
		await page.getByRole('button', { name: 'Run now' }).click();
		for (const field of await page.getByRole('dialog', { name: /^Run .* now$/ }).getByLabel(/^Password for/).all()) await field.fill(process.env.IRIS_PASSWORD ?? 'SYS');
		await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
		await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED', { timeout: 120_000 });

		const guid = new URL(page.url()).searchParams.get('run')!;
		const steps = await stepsOf(request, guid);
		const auth = { Authorization: `Bearer ${await token(request)}` };
		const roles = (await (await request.get('/api/admin/v2/security/roles', { headers: auth })).json()).result;
		const resources = (await (await request.get('/api/admin/v2/security/resources', { headers: auth })).json()).result;
		// The totals are in the summary (the details may be cut to fit the stored result).
		expect(steps['01'].result.summary.roles).toBe(roles.length);
		expect(steps['01'].result.summary.resources).toBe(resources.length);
		expect(steps['02'].executedOn).toBe('iris-target');
		expect(steps['02'].result.summary.roles).toBeGreaterThan(0);
		expect(steps['02'].result.instance).toBe('iris-target');
	} finally {
		deleteFlowWithRuns(id, name);
	}
});

test('us29 C — OAuth not configured is a completed step with the platform text', async ({ page, request }) => {
	const name = `us29-oauth ${Date.now()}`;
	const id = await seed(request, name, [step('01', 'oauth-inventory')]);
	try {
		const run = await runToEnd(request, id);
		const steps = await stepsOf(request, run.guid);
		expect(steps['01'].state).toBe('completed');
		expect(steps['01'].result.details.configured).toBe(false);
		expect(steps['01'].result.details.serverMessage).toContain('ERROR #8864');
		await signInAt(page, `?flow=${id}&run=${run.guid}`);
		await page.locator('.svelte-flow__node[data-id="01"]').getByRole('button', { name: 'Result' }).click();
		await expect(page.getByTestId('result-panel')).toContainText('ERROR #8864');
	} finally {
		deleteFlowWithRuns(id, name);
	}
});

test('us29 D — the three types are in the Security group; warnDays out of range is a field error', async ({ page, request }) => {
	const name = `us29-params ${Date.now()}`;
	const id = await seedFlow(request, {
		name,
		defaultCategory: 'Default',
		steps: [step('01', 'certificate-expiry-check', { warnDays: 0 })],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	});
	try {
		await signIn(page, `?flow=${id}`);
		const palette = page.getByLabel('Step types');
		for (const type of ['certificate-expiry-check', 'permissions-inventory', 'oauth-inventory']) {
			await expect(await paletteEntry(page, type)).toBeEnabled();
		}
		await page.locator('.svelte-flow__node[data-id="01"] h3').click();
		await flowButton(page, 'validate').click();
		await expect(page.getByLabel('Inspector', { exact: true }).getByTestId('param-error-warnDays')).toContainText('between 1 and 365');
	} finally {
		deleteFlowWithRuns(id, name);
	}
});
