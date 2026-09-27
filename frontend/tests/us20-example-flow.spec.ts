/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type APIRequestContext, type Page, type Route } from '@playwright/test';
import { assertDevInstance, deleteFlowWithRuns, EXAMPLE_FLOW_NAME } from './iris';
import { envelope, PASSWORD, seedFlow, signIn, token, USER } from './support';

// spec 010 User Story 4 — Run a ready-made example flow (FR-015…FR-019, SC-004, SC-005).

const EVIDENCE = '../specs/010-canvas-onboarding-usability/evidence';
const API = '/csp/sentai/api/v1';
const FLOWS = `**${API}/flows`;

async function listFlows(request: APIRequestContext): Promise<Array<{ id: string; name: string }>> {
	const res = await request.get(`${API}/flows`, { headers: { Authorization: `Bearer ${await token(request)}` } });
	expect(res.status()).toBe(200);
	return res.json();
}

const examples = async (request: APIRequestContext) =>
	(await listFlows(request)).filter((f) => f.name.toLowerCase() === EXAMPLE_FLOW_NAME.toLowerCase());

/** GET /flows answers `[]` for the next `times` reads only — "no saved flows" on a shared stack. */
async function emptyListFor(page: Page, times: number) {
	let left = times;
	await page.route(FLOWS, (route: Route) => {
		if (route.request().method() === 'GET' && left > 0) {
			left--;
			return route.fulfill({ status: 200, json: [] });
		}
		return route.continue();
	});
}

const invitation = (page: Page) => page.getByTestId('example-invitation');
const inspector = (page: Page) => page.getByLabel('Inspector', { exact: true });
const chip = (page: Page, stepId: string) => page.locator(`.svelte-flow__node[data-id="${stepId}"]`).getByTestId('state-chip');

test.beforeAll(() => {
	// The helper that deletes flows with runs refuses anything but this feature's test flows on the
	// local dev instance (tasks.md T038).
	expect(() => assertDevInstance('Production nightly checks')).toThrow(/^refused/);
	expect(() => deleteFlowWithRuns('1', 'Production nightly checks')).toThrow(/^refused/);
	const saved = process.env.SENTAI_CONTAINER;
	process.env.SENTAI_CONTAINER = 'other';
	try {
		expect(() => deleteFlowWithRuns('1', EXAMPLE_FLOW_NAME)).toThrow(/^refused: container other/);
	} finally {
		if (saved === undefined) delete process.env.SENTAI_CONTAINER;
		else process.env.SENTAI_CONTAINER = saved;
	}
});

test.beforeEach(async ({ request }) => {
	for (const flow of await examples(request)) deleteFlowWithRuns(flow.id, flow.name);
});

test('us20 example — offered on the empty canvas, opened, validated with 0 errors and run to the end (SC-005)', async ({ page }) => {
	await emptyListFor(page, 1); // the boot-time read: an instance with no flows
	await signIn(page);
	await expect(invitation(page)).toBeVisible();
	await expect(invitation(page).getByRole('button', { name: 'Start from scratch' })).toBeVisible();

	const started = Date.now();
	await invitation(page).getByRole('button', { name: 'Open example flow' }).click();
	await expect(page.getByLabel('Flow name')).toHaveValue(EXAMPLE_FLOW_NAME);
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toMatch(/^\d+$/);
	await expect(invitation(page)).toHaveCount(0);

	// Two parallel read-only steps, parameters filled in (scenario 4.2, FR-015).
	await expect(page.locator('.svelte-flow__node')).toHaveCount(2);
	await expect(page.locator('.svelte-flow__edge')).toHaveCount(0);
	await expect(page.locator('.svelte-flow__node[data-id="01"]')).toContainText('Storage headroom check');
	await expect(page.locator('.svelte-flow__node[data-id="02"]')).toContainText('Database size report');
	await page.locator('.svelte-flow__node[data-id="01"] h3').click();
	await expect(inspector(page).getByLabel('MinFreePercent')).toHaveValue('10');

	// Scenario 4.3.
	await page.getByRole('button', { name: 'Validate flow' }).click();
	await expect(page.getByRole('status').filter({ hasText: 'Flow is valid — no errors, no warnings.' })).toBeVisible();

	// Scenario 4.4: the normal run sign-in, no destructive confirmation, followed to the end.
	await page.getByRole('button', { name: 'Run now' }).click();
	await expect(page.getByTestId('typed-confirmations')).toHaveCount(0);
	await page.getByLabel(`Password for ${USER}`).fill(PASSWORD);
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
	await expect(page.getByTestId('run-state')).toBeVisible();
	await expect(chip(page, '01')).toHaveText('COMPLETED', { timeout: 60_000 });
	await expect(chip(page, '02')).toHaveText('COMPLETED', { timeout: 60_000 });
	await expect(page.getByTestId('run-state')).toHaveText('RUN COMPLETED', { timeout: 30_000 });
	const elapsedMs = Date.now() - started;

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us20-example.json`,
		envelope(
			'us20-example',
			{ method: 'POST', path: '/flows/{id}/dispatch' },
			{ validation: { errors: [], warnings: [] }, steps: { '01': 'completed', '02': 'completed' }, run: 'completed', elapsedMs },
			[
				'Scripted path from "Open example flow" to the run finishing (the automated part of SC-004; the 2-minute SC is timed manually, quickstart §4).',
				'No typed-confirmation fieldset was shown: neither step type is destructive (SC-005).'
			]
		)
	);
});

test('us20 idempotent — opening the example again opens the same flow; never a duplicate (FR-017, FR-018)', async ({ page }) => {
	await emptyListFor(page, 1);
	await signIn(page);
	await invitation(page).getByRole('button', { name: 'Open example flow' }).click();
	await expect(page.getByLabel('Flow name')).toHaveValue(EXAMPLE_FLOW_NAME);
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toMatch(/^\d+$/);
	const id = new URL(page.url()).searchParams.get('flow');

	// An edit is kept like any flow's (scenario 4.6).
	const node = page.locator('.svelte-flow__node[data-id="02"]');
	const box = (await node.boundingBox())!;
	await page.mouse.move(box.x + 30, box.y + 12);
	await page.mouse.down();
	await page.mouse.move(box.x + 30, box.y + 172, { steps: 8 });
	await page.mouse.up();
	await page.getByRole('button', { name: 'Save flow' }).click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');

	// New flow, then the example again from Open flow… with no flows listed: the same id.
	await page.getByRole('banner').getByRole('button', { name: 'More' }).click();
	await page.getByRole('menuitem', { name: 'New flow' }).click();
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toBeNull();
	await emptyListFor(page, 1);
	await page.getByRole('banner').getByRole('button', { name: 'Open flow…' }).click();
	const dialog = page.getByRole('dialog', { name: 'Open flow' });
	await dialog.getByRole('button', { name: 'Open example flow' }).click();
	await expect(page.getByLabel('Flow name')).toHaveValue(EXAMPLE_FLOW_NAME);
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toBe(id);
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');
	expect((await examples(page.request)).map((f) => f.id)).toEqual([id]);

	// It is listed like any other flow.
	await page.getByRole('banner').getByRole('button', { name: 'Open flow…' }).click();
	await dialog.getByLabel('Filter by name').fill(EXAMPLE_FLOW_NAME);
	await expect(dialog.getByTestId('flow-row')).toHaveCount(1);
	await expect(dialog.getByTestId('flow-row')).toHaveAttribute('aria-current', 'true');
});

test('us20 guard — opening the example over unsaved edits asks first (FR-006)', async ({ page }) => {
	const id = await seedFlow(page.request, {
		name: `us20-guard-${Date.now()}`,
		defaultCategory: 'Default',
		steps: [{ id: '01', type: 'db-size-report', taskName: 'Sizes', namespace: '%SYS', wqmCategory: 'Default' }],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	});
	await signIn(page, `?flow=${id}`);
	await page.locator('[data-step-type="db-size-report"]').click();
	await emptyListFor(page, 1);
	await page.getByRole('banner').getByRole('button', { name: 'Open flow…' }).click();
	await page.getByRole('dialog', { name: 'Open flow' }).getByRole('button', { name: 'Open example flow' }).click();
	const guard = page.getByRole('dialog', { name: /^Save changes to / });
	await expect(guard).toBeVisible();
	await guard.getByRole('button', { name: 'Cancel' }).click();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(2);
	expect(new URL(page.url()).searchParams.get('flow')).toBe(id);
	expect(await examples(page.request)).toEqual([]);
});

test('us20 not offered — a missing, unavailable or destructive step type, or a refused list, hides it (FR-019)', async ({ page }) => {
	await signIn(page);
	for (const change of ['absent', 'unavailable', 'destructive'] as const) {
		await page.unrouteAll({ behavior: 'ignoreErrors' });
		await page.route(`**${API}/catalog/step-types`, async (route) => {
			const types = (await (await route.fetch()).json()) as Array<Record<string, unknown>>;
			const changed = types
				.filter((t) => change !== 'absent' || t.type !== 'db-size-report')
				.map((t) =>
					t.type !== 'db-size-report' ? t : change === 'unavailable' ? { ...t, available: false } : { ...t, destructive: true }
				);
			return route.fulfill({ status: 200, json: changed });
		});
		await page.route(FLOWS, (route) => (route.request().method() === 'GET' ? route.fulfill({ status: 200, json: [] }) : route.continue()));
		await page.reload();
		await expect(invitation(page), change).toBeVisible();
		await expect(invitation(page).getByRole('button', { name: 'Open example flow' }), change).toHaveCount(0);
		await expect(invitation(page).getByRole('button', { name: 'Start from scratch' }), change).toBeVisible();
		await page.getByRole('banner').getByRole('button', { name: 'Open flow…' }).click();
		const dialog = page.getByRole('dialog', { name: 'Open flow' });
		await expect(dialog.getByRole('button', { name: 'New flow' }), change).toBeVisible();
		await expect(dialog.getByRole('button', { name: 'Open example flow' }), change).toHaveCount(0);
		await page.keyboard.press('Escape');
	}

	// A refused list: no invitation at all — nothing is offered on a guess (research R-4.4).
	await page.unrouteAll({ behavior: 'ignoreErrors' });
	await page.route(FLOWS, (route) =>
		route.request().method() === 'GET'
			? route.fulfill({ status: 403, json: { status: 403, title: 'Forbidden', detail: 'not permitted (spec 010 probe)' } })
			: route.continue()
	);
	await page.reload();
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	await expect(invitation(page)).toHaveCount(0);
});
