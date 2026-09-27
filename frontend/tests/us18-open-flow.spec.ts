/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { envelope, seedFlow, signIn, signInAt, token } from './support';

// spec 010 User Story 2 — Open a saved flow (FR-001…FR-003, FR-006, FR-008, SC-002).

const EVIDENCE = '../specs/010-canvas-onboarding-usability/evidence';

function oneStepFlow(name: string) {
	return {
		name,
		defaultCategory: 'Default',
		steps: [{ id: '01', type: 'db-size-report', taskName: 'Sizes', namespace: '%SYS', wqmCategory: 'Default' }],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	};
}

const dialog = (page: Page) => page.getByRole('dialog', { name: 'Open flow' });
const rows = (page: Page) => dialog(page).getByTestId('flow-row');
const flowIdIn = (page: Page) => new URL(page.url()).searchParams.get('flow');

async function openList(page: Page) {
	await page.getByRole('banner').getByRole('button', { name: 'Open flow…' }).click();
	await expect(dialog(page)).toBeVisible();
}

/** Two flows saved at different seconds, the second one newer. */
async function seedPair(page: Page) {
	const ts = Date.now();
	const older = `us18-${ts}-alpha`;
	const newer = `us18-${ts}-beta`;
	const olderId = await seedFlow(page.request, oneStepFlow(older));
	await page.waitForTimeout(1100); // savedAt has a one-second resolution
	const newerId = await seedFlow(page.request, oneStepFlow(newer));
	return { ts, older, newer, olderId, newerId };
}

test('us18 list — newest first, filter ignores case, pick opens and addresses the flow; ≤ 3 actions (SC-002)', async ({ page, browser }) => {
	const { ts, older, newer, olderId, newerId } = await seedPair(page);
	await signIn(page);
	expect(flowIdIn(page)).toBeNull();

	let actions = 0;
	await openList(page);
	actions++;
	await dialog(page).getByLabel('Filter by name').fill(`us18-${ts}`);
	actions++;
	await expect(rows(page)).toHaveCount(2);
	await expect(rows(page).nth(0)).toContainText(newer);
	await expect(rows(page).nth(1)).toContainText(older);
	await expect(rows(page).nth(0)).toContainText('rev 1');
	await expect(rows(page).nth(0)).toContainText(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
	await expect(dialog(page).getByTestId('flow-count')).toHaveText(/^2 of \d+ flows$/);

	// Case-insensitive substring (scenario 2.2).
	await dialog(page).getByLabel('Filter by name').fill(`${ts}-ALPHA`);
	await expect(rows(page)).toHaveCount(1);
	await rows(page).first().click();
	actions++;
	await expect(dialog(page)).toBeHidden();
	await expect(page.getByLabel('Flow name')).toHaveValue(older);
	expect(flowIdIn(page)).toBe(olderId);
	expect(actions).toBeLessThanOrEqual(3);

	// The open flow is marked (scenario 2.1).
	await openList(page);
	await dialog(page).getByLabel('Filter by name').fill(`us18-${ts}`);
	await expect(rows(page).filter({ hasText: older })).toHaveAttribute('aria-current', 'true');
	await expect(rows(page).filter({ hasText: newer })).not.toHaveAttribute('aria-current', 'true');

	// Pick the other one; back and forward follow the address (FR-003).
	await rows(page).filter({ hasText: newer }).click();
	await expect(page.getByLabel('Flow name')).toHaveValue(newer);
	expect(flowIdIn(page)).toBe(newerId);
	await page.goBack();
	await expect(page.getByLabel('Flow name')).toHaveValue(older);
	await page.goForward();
	await expect(page.getByLabel('Flow name')).toHaveValue(newer);

	// A shared link opens the same flow in a fresh page (the reload case is us19's).
	const other = await browser.newPage();
	await signInAt(other, `?flow=${newerId}`);
	await expect(other.getByLabel('Flow name')).toHaveValue(newer);
	await other.close();

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us18-open-flow.json`,
		envelope('us18-open-flow', { method: 'GET', path: '/flows' }, { order: [newer, older], picked: olderId, actions }, [
			'Open flow… listed the newer flow first; the filter matched case-insensitively.',
			`SC-002: ${actions} actions from the canvas (open list, filter, pick).`
		])
	);
});

test('us18 guard — picking another flow over unsaved edits asks first (FR-006)', async ({ page }) => {
	const { ts, older, newer, olderId } = await seedPair(page);
	await signIn(page, `?flow=${olderId}`);
	await page.locator('[data-step-type="db-size-report"]').click();
	await openList(page);
	await dialog(page).getByLabel('Filter by name').fill(`us18-${ts}`);
	await rows(page).filter({ hasText: newer }).click();
	const guard = page.getByRole('dialog', { name: /^Save changes to / });
	await expect(guard).toBeVisible();
	await guard.getByRole('button', { name: 'Cancel' }).click();
	await expect(page.getByLabel('Flow name')).toHaveValue(older);
	await expect(page.locator('.svelte-flow__node')).toHaveCount(2);
	expect(flowIdIn(page)).toBe(olderId);
});

test('us18 empty and refused — no flows offers New flow; a refusal is shown as the platform gave it (FR-008)', async ({ page }) => {
	await signIn(page);

	await page.route('**/csp/sentai/api/v1/flows', (route) =>
		route.request().method() === 'GET' ? route.fulfill({ status: 200, json: [] }) : route.continue()
	);
	await openList(page);
	await expect(dialog(page).getByText('No saved flows yet.')).toBeVisible();
	await expect(dialog(page).getByRole('button', { name: 'New flow' })).toBeVisible();
	await page.keyboard.press('Escape');
	await page.unroute('**/csp/sentai/api/v1/flows');

	// The shared stack cannot deny the list to a signed-in operator on demand, so the refusal is
	// routed; what is asserted is that its words reach the dialog unchanged.
	const detail = 'User e2e is not permitted to list flows (probe for spec 010 FR-008)';
	await page.route('**/csp/sentai/api/v1/flows', (route) =>
		route.request().method() === 'GET'
			? route.fulfill({ status: 403, json: { status: 403, title: 'Forbidden', detail } })
			: route.continue()
	);
	await openList(page);
	await expect(dialog(page).getByRole('alert')).toHaveText(detail);
	await expect(rows(page)).toHaveCount(0);
});

test('us18 unreadable address — the canvas opens with the reason and a way on (edge case)', async ({ page }) => {
	await signIn(page, '?flow=99999999');
	await expect(page.getByRole('status').filter({ hasText: "Flow '99999999' does not exist" })).toBeVisible();
	const panel = page.getByTestId('flow-unreadable');
	await expect(panel).toBeVisible();
	await expect(panel.getByRole('button', { name: 'Open flow…' })).toBeVisible();
	await expect(panel.getByRole('button', { name: 'New flow' })).toBeVisible();
	await panel.getByRole('button', { name: 'New flow' }).click();
	await expect(panel).toHaveCount(0);
	await expect.poll(() => flowIdIn(page)).toBeNull();
});

test('us18 performance — 5,000 flows open within 1 s and filter within 150 ms, no long task > 200 ms', async ({ page }) => {
	const many = Array.from({ length: 5000 }, (_, i) => ({
		id: String(900000 + i),
		name: `perf-${String(i + 1).padStart(5, '0')}`,
		revision: 1 + (i % 7),
		savedAt: `2026-09-${String(1 + (i % 27)).padStart(2, '0')} ${String(i % 24).padStart(2, '0')}:${String(i % 60).padStart(2, '0')}:00`,
		savedBy: 'perf',
		nextRun: ''
	}));
	await signIn(page);

	// What the real platform takes to return the whole list (the dev instance holds ~5,000 flows),
	// timed in the page with a credential of the same operator.
	const bearer = await token(page.request);
	const server = await page.evaluate(async (auth) => {
		const t0 = performance.now();
		const res = await fetch('/csp/sentai/api/v1/flows', { headers: { Authorization: `Bearer ${auth}` } });
		const rows = ((await res.json()) as unknown[]).length;
		return { ms: performance.now() - t0, status: res.status, rows };
	}, bearer);
	expect(server.status).toBe(200);
	const serverMs = server.ms;

	// The client side is measured on exactly 5,000 rows; Playwright's route transfer is excluded
	// (it is Playwright's IPC, not the app), and so is its locator engine: timings are in-page.
	await page.route('**/csp/sentai/api/v1/flows', (route) =>
		route.request().method() === 'GET' ? route.fulfill({ status: 200, json: many }) : route.continue()
	);
	const timing = await page.evaluate(async () => {
		const long: number[] = [];
		new PerformanceObserver((list) => {
			for (const e of list.getEntries()) long.push(e.duration);
		}).observe({ type: 'longtask' });
		performance.clearResourceTimings();
		const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
		const button = [...document.querySelectorAll<HTMLButtonElement>('header button')].find((b) => b.textContent?.trim() === 'Open flow…')!;
		const clicked = performance.now();
		button.click();
		while (!document.querySelector('[data-testid="flow-row"]')) await frame();
		const rowsAt = performance.now();
		const response = (performance.getEntriesByType('resource') as PerformanceResourceTiming[]).find((e) =>
			e.name.endsWith('/csp/sentai/api/v1/flows')
		)!;
		const count = document.querySelector('[data-testid="flow-count"]')!.textContent;

		const input = document.querySelector<HTMLInputElement>('#open-flow-filter')!;
		const t0 = performance.now();
		input.value = 'perf-04';
		input.dispatchEvent(new Event('input', { bubbles: true }));
		await frame();
		const filterMs = performance.now() - t0;
		await frame();
		return {
			renderMs: rowsAt - Math.max(clicked, response.responseEnd),
			count,
			filterMs,
			filteredCount: document.querySelector('[data-testid="flow-count"]')!.textContent,
			longestTaskMs: Math.max(0, ...long)
		};
	});
	const openMs = serverMs + timing.renderMs;

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us18-perf.json`,
		JSON.stringify(
			{
				flows: many.length,
				serverRows: server.rows,
				serverListMs: Math.round(serverMs),
				clientRenderMs: Math.round(timing.renderMs),
				openMs: Math.round(openMs),
				filterMs: Math.round(timing.filterMs),
				longestTaskMs: Math.round(timing.longestTaskMs),
				notes: [
					'openMs = the real GET /flows on the dev instance (~5,000 flows) + the client render of 5,000 routed rows after the response.',
					'Timed in the page: Playwright route transfer and its locator engine are not part of the app.'
				]
			},
			null,
			2
		)
	);
	expect(timing.count).toBe('5000 of 5000 flows');
	expect(timing.filteredCount).toBe('1000 of 5000 flows');
	expect(openMs).toBeLessThan(1000);
	expect(timing.filterMs).toBeLessThan(150);
	expect(timing.longestTaskMs).toBeLessThanOrEqual(200);
});
