/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { envelope, PASSWORD, seedFlow, signIn, token, USER } from './support';

// spec 009 User Stories 2–5 over the spec 008 API, on the compose stack's iris-target.

const EVIDENCE = '../specs/009-canvas-distributed-targets/evidence';
const TARGET = 'iris-target';

async function api(page: Page, method: string, path: string, data?: object) {
	const res = await page.request.fetch(`/csp/sentai/api/v1${path}`, {
		method,
		headers: { Authorization: `Bearer ${await token(page.request)}` },
		...(data ? { data } : {})
	});
	return { status: res.status(), body: res.status() === 204 ? null : await res.json() };
}

const ic = (id: string, taskName: string, extra: Record<string, unknown> = {}) => ({
	id,
	type: 'integrity-check',
	taskName,
	namespace: 'USER',
	runAsUser: 'irisadm',
	wqmCategory: 'Default',
	timeoutMinutes: 30,
	databaseDirectory: '/usr/irissys/mgr/user/',
	...extra
});

const node = (page: Page, id: string) => page.locator(`.svelte-flow__node[data-id="${id}"]`);

test.beforeAll(async ({ browser }) => {
	// The shared demo target (spec 008 quickstart registers it; make sure it is there and online).
	const page = await browser.newPage({ baseURL: test.info().project.use.baseURL });
	if ((await api(page, 'GET', `/targets/${TARGET}`)).status === 404) {
		expect((await api(page, 'POST', '/targets', { name: TARGET, baseUrl: 'http://iris-target:52773', description: 'demo target (compose)' })).status).toBe(201);
	}
	await api(page, 'POST', `/targets/${TARGET}/online`, { online: true });
	await page.close();
});

test('us16 place — Run on is offered for remote-capable types only, saved, and badged on the node', async ({ page }) => {
	const id = await seedFlow(page.request, {
		name: `us16 place ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [ic('01', 'IC on the target'), { id: '02', type: 'db-size-report', taskName: 'DB sizes', namespace: '%SYS', runAsUser: 'irisadm', wqmCategory: 'Default' }],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 }, '02': { x: 40, y: 240 } } }
	});
	await signIn(page, `?flow=${id}`);

	await node(page, '02').locator('h3').click();
	await expect(page.getByLabel('Run on')).toHaveCount(0);
	await expect(page.getByTestId('runs-locally-note')).toContainText('runs on this instance only');

	await node(page, '01').locator('h3').click();
	const runOn = page.getByLabel('Run on');
	await expect(runOn.locator('option')).toContainText(['Local (this instance)', TARGET]);
	await runOn.selectOption(TARGET);
	await expect(node(page, '01').getByTestId('target-badge')).toHaveText(TARGET);
	await expect(node(page, '02').getByTestId('target-badge')).toHaveCount(0);
	await page.getByRole('button', { name: 'Save flow' }).click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');

	const saved = (await api(page, 'GET', `/flows/${id}`)).body;
	expect(saved.steps.find((s: { id: string }) => s.id === '01').target).toBe(TARGET);
	expect('target' in saved.steps.find((s: { id: string }) => s.id === '02')).toBe(false);

	// Back to Local removes it.
	await runOn.selectOption({ label: 'Local (this instance)' });
	await page.getByRole('button', { name: 'Save flow' }).click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 3');
	expect('target' in (await api(page, 'GET', `/flows/${id}`)).body.steps.find((s: { id: string }) => s.id === '01')).toBe(false);
});

test('us16 findings — an unknown target is an error on its node; an unverified one only warns', async ({ page }) => {
	const id = await seedFlow(page.request, {
		name: `us16 findings ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [ic('01', 'On an unknown target', { target: 'no-such-target' }), ic('02', 'On the demo target', { target: TARGET })],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 }, '02': { x: 40, y: 260 } } }
	});
	await signIn(page, `?flow=${id}`);
	await page.getByRole('button', { name: 'Validate flow' }).click();
	await expect(node(page, '01')).toContainText("names target 'no-such-target', which is not registered");
	await expect(node(page, '02')).toContainText(`Target '${TARGET}' was not checked`);
	await expect(page.getByTestId('status-errors')).toContainText('#01');
});

test('us16 run — one password per target at Run now; the demo flow completes with executedOn per node', async ({ page }) => {
	test.setTimeout(420_000);
	const id = await seedFlow(page.request, {
		name: `us16 demo ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			ic('01', 'IC USER (primary)'),
			ic('02', 'IC IRISAPP (primary)', { namespace: 'IRISAPP', databaseDirectory: '/data/IRISAPP_DATA/' }),
			ic('03', 'IC USER (iris-target)', { target: TARGET, databaseDirectory: '' }),
			ic('04', 'IC after fan-in')
		],
		edges: [
			{ source: '01', target: '04' },
			{ source: '02', target: '04' },
			{ source: '03', target: '04' }
		],
		joins: [{ target: '04', policy: 'ALL_MUST_SUCCEED' }],
		canvasGeometry: { nodes: { '01': { x: 0, y: 0 }, '02': { x: 0, y: 200 }, '03': { x: 0, y: 400 }, '04': { x: 340, y: 200 } } }
	});
	await signIn(page, `?flow=${id}`);
	await page.getByRole('button', { name: 'Run now' }).click();
	const dialog = page.getByRole('dialog');
	const targetPassword = dialog.getByLabel(`Password for ${USER} on ${TARGET}`);
	await expect(targetPassword).toBeVisible();
	await expect(dialog.getByLabel(/Password for .* on /)).toHaveCount(1);

	// A wrong target password: its refusal, verbatim; nothing dispatched.
	await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD);
	await targetPassword.fill('not-the-password');
	await dialog.getByRole('button', { name: 'Dispatch', exact: true }).click();
	await expect(dialog.getByRole('alert')).toContainText(`Target ${TARGET}: HTTP 401 — no reason given`);
	expect(((await api(page, 'GET', `/runs?flowId=${id}`)).body as unknown[]).length).toBe(0);

	// The right ones dispatch; the live run shows where each step runs.
	await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD);
	await targetPassword.fill(PASSWORD);
	const dispatched = page.waitForResponse((r) => r.url().endsWith(`/flows/${id}/dispatch`));
	await dialog.getByRole('button', { name: 'Dispatch', exact: true }).click();
	const response = await dispatched;
	expect(response.status()).toBe(202);
	const sent = JSON.parse(response.request().postData() ?? '{}');
	expect(sent.targetCredentials.map((c: { target: string }) => c.target)).toEqual([TARGET]);
	const guid = String((await response.json()).guid);

	await expect(page.getByTestId('count-line')).toHaveText('4 completed · 0 failed · 0 running · 0 queued', { timeout: 360_000 });
	const run = (await api(page, 'GET', `/runs/${guid}`)).body;
	for (const s of run.steps as Array<{ stepId: string; executedOn: string }>) {
		await expect(page.locator(`[data-step-id="${s.stepId}"]`).getByTestId('executed-on')).toHaveText(s.executedOn);
	}
	expect(run.steps.find((s: { stepId: string }) => s.stepId === '03').executedOn).toBe(TARGET);

	mkdirSync(EVIDENCE, { recursive: true });
	await page.screenshot({ path: `${EVIDENCE}/us3-remote-run.png` });
	writeFileSync(
		`${EVIDENCE}/us3-remote-run.json`,
		envelope('us3-remote-run', { method: 'POST', path: `/flows/${id}/dispatch`, targets: sent.targetCredentials.map((c: { target: string }) => c.target) }, { status: 202, body: run }, [
			'Dispatched from the canvas: one run password and one password for iris-target; a wrong target password was refused verbatim first, with no run created.',
			'Each node showed executedOn equal to the run read. No token or password is recorded.'
		])
	);
});
