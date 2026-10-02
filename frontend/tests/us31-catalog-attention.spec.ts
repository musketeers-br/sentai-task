/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import type { WireCatalogPage, WireCatalogTask } from '../src/lib/catalog/catalog';
import { apiTask, catalog, detail } from './catalog-support';
import { deleteFlow } from './iris';
import { canonicalFlow, entry, envelope, expectNoSeriousA11y, nativeTaskIds, scheduleFlow, seedFlow, signInAt, token, unscheduleFlow } from './support';

// Spec 023 User Story 2 — the Task catalog points at what needs attention (FR-015–FR-020a;
// board *Proposed — Task catalog*). Expected numbers are read from the API, never hard-coded.
// Suspend/Resume only ever touches a task this file scheduled itself.

const EVIDENCE = '../specs/023-canvas-design-refresh/evidence';

async function apiPage(request: APIRequestContext, query = ''): Promise<WireCatalogPage & { counts: { suspended: number; destructive: number; unclassified: number } }> {
	const res = await request.get(`/csp/sentai/api/v1/catalog/tasks${query}`, { headers: { Authorization: `Bearer ${await token(request)}` } });
	expect(res.status(), await res.text()).toBe(200);
	return res.json();
}

async function declaredClasses(request: APIRequestContext): Promise<Set<string>> {
	const res = await request.get('/csp/sentai/api/v1/catalog/step-types', { headers: { Authorization: `Bearer ${await token(request)}` } });
	const types = (await res.json()) as Array<{ class: string }>;
	return new Set(types.map((t) => t.class).filter(Boolean));
}

const row = (page: Page, taskId: number | string) => catalog(page).locator(`[data-testid="catalog-row"][data-task-id="${taskId}"]`);

let flowId = '';
let ownTaskId = 0;

test.beforeAll(async ({ request }) => {
	const base = canonicalFlow(`us31 suspend ${Date.now()}`);
	flowId = await seedFlow(request, { ...base, steps: base.steps.slice(0, 1), edges: [], joins: [], canvasGeometry: { nodes: {} } });
	const res = await scheduleFlow(request, flowId);
	expect(res.status(), await res.text()).toBe(201);
	ownTaskId = Number((await res.json()).taskId);
});

test.afterAll(async ({ request }) => {
	await unscheduleFlow(request, flowId);
	deleteFlow(flowId);
	expect(await nativeTaskIds(request, flowId)).toEqual([]);
});

test('counts, the unclassified filter and the footer come from the API (FR-015, FR-016, FR-019)', async ({ page }) => {
	const wire = await apiPage(page.request);
	await signInAt(page, '?view=catalog');
	await expect(page.getByTestId('catalog-count')).toHaveText(`${wire.matched} of ${wire.total} tasks`);
	await expect(page.getByTestId('catalog-freshness')).toHaveText(/^updated \d+ s ago$/);
	await expect(page.getByTestId('count-suspended')).toHaveText(String(wire.counts.suspended));
	await expect(page.getByTestId('count-destructive')).toHaveText(String(wire.counts.destructive));
	await expect(page.getByTestId('count-unclassified')).toHaveText(String(wire.counts.unclassified));
	await expect(page.getByTestId('catalog-footer')).toHaveText(
		`sorted by next run · ${wire.counts.destructive} destructive · ${wire.counts.suspended} suspended · ${wire.counts.unclassified} unclassified`
	);
	await page.screenshot({ path: `${EVIDENCE}/us31-catalog-counts.png` });

	// The unclassified filter lists exactly what the API keeps; the counts do not move.
	const unclassified = await apiPage(page.request, '?unclassifiedOnly=1');
	await page.getByLabel('unclassified').check();
	await expect(page).toHaveURL(/unclassifiedOnly=1/);
	await expect(page.getByTestId('catalog-count')).toHaveText(`${unclassified.matched} of ${unclassified.total} tasks`);
	await expect(catalog(page).getByTestId('catalog-row')).toHaveCount(Number(unclassified.matched));
	await expect(page.getByTestId('unclassified-note')).toContainText('step-type catalog');
	await expect(page.getByTestId('count-unclassified')).toHaveText(String(wire.counts.unclassified));
	for (const item of unclassified.items) await expect(row(page, item.taskId)).toBeVisible();

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us31-counts.json`,
		envelope(
			'us31-counts',
			{ method: 'GET', url_path: '/csp/sentai/api/v1/catalog/tasks', also: '?unclassifiedOnly=1' },
			{ total: wire.total, matched: wire.matched, counts: wire.counts, unclassifiedMatched: unclassified.matched },
			['The screen showed these numbers as the API sent them (SC-005).']
		)
	);
});

test('the address preselects the filters (Overview links)', async ({ page }) => {
	await signInAt(page, '?view=catalog&filter=suspended&unclassifiedOnly=1');
	await expect(page.getByRole('radio', { name: /Suspended/ })).toBeChecked();
	await expect(page.getByLabel('unclassified')).toBeChecked();
	const wire = await apiPage(page.request, '?filter=suspended&unclassifiedOnly=1');
	await expect(page.getByTestId('catalog-count')).toHaveText(`${wire.matched} of ${wire.total} tasks`);
});

test('detail — description, why destructive, created outside SentaiTask, last runs (FR-017, FR-020a)', async ({ page }) => {
	const wire = await apiPage(page.request);
	const destructive = wire.items.find((t: WireCatalogTask) => t.destructive && !t.origin && t.class === '%SYS.Task.PurgeTaskHistory');
	test.skip(!destructive, 'the instance has no Purge Tasks task');
	await signInAt(page, `?view=catalog&task=${destructive!.taskId}`);
	const pane = detail(page);
	await expect(pane.getByTestId('destructive-seal')).toBeVisible();
	await expect(pane.getByTestId('destructive-reason')).toContainText('Permanently removes task history records.');
	await expect(pane.getByTestId('destructive-reason')).toContainText('classified from the step-type registry · not editable here');
	await expect(pane.getByTestId('outside-mark')).toHaveText('created outside SentaiTask');
	const item = (await apiTask(page.request, destructive!.taskId)).wire;
	await expect(pane.getByTestId('detail-field-description')).toHaveText(item.description ?? '—');
	await page.screenshot({ path: `${EVIDENCE}/us31-detail-destructive.png` });

	// A task that never ran says so.
	for (const candidate of wire.items.filter((t: WireCatalogTask) => t.lastFinished === '')) {
		const { wire: one } = await apiTask(page.request, candidate.taskId);
		if (Array.isArray(one.recentRuns) && one.recentRuns.length === 0) {
			await page.goto(page.url().replace(/task=\d+/, `task=${candidate.taskId}`));
			await expect(detail(page).getByTestId('recent-runs')).toHaveText(/No run recorded\. This task has never executed on this instance\./);
			break;
		}
	}
});

test('Add to a flow — a declared class becomes a step; any other says why (FR-018)', async ({ page }) => {
	const wire = await apiPage(page.request);
	const declared = await declaredClasses(page.request);
	const integrity = wire.items.find((t: WireCatalogTask) => t.class === '%SYS.Task.IntegrityCheck');
	const undeclared = wire.items.find((t: WireCatalogTask) => t.class && !declared.has(t.class));

	if (undeclared) {
		await signInAt(page, `?view=catalog&task=${undeclared.taskId}`);
		await expect(detail(page).getByTestId('add-to-flow')).toBeDisabled();
		await expect(detail(page).getByTestId('add-to-flow-reason')).toHaveText('no step type declares this class');
	}

	test.skip(!integrity, 'the instance has no Integrity Check task');
	if (undeclared) await page.goto(entry(`?view=catalog&task=${integrity!.taskId}`));
	else await signInAt(page, `?view=catalog&task=${integrity!.taskId}`);
	await expect(detail(page).getByTestId('add-to-flow')).toBeEnabled();
	await detail(page).getByTestId('add-to-flow').click();
	await expect(page.getByRole('toolbar', { name: 'Flow' })).toBeVisible();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(1);
	await expect(page.getByTestId('flow-summary')).toHaveText('1 step · 0 joins · 0 destructive');
	await expect(page.getByTestId('flow-meta')).toHaveText('unsaved');
	await page.locator('.svelte-flow__node').first().click();
	await expect(page.locator('#insp-namespace')).toHaveValue(integrity!.namespace);
});

test('Suspend/Resume — one switch, confirmed first; Cancel sends nothing; a refusal is verbatim (FR-020)', async ({ page }) => {
	const before = await apiPage(page.request);
	await signInAt(page, `?view=catalog&task=${ownTaskId}`);
	const pane = detail(page);
	const toggle = pane.getByRole('switch');
	await expect(toggle).not.toBeChecked();

	// Cancel: the dialog closes and no call is made.
	let calls = 0;
	page.on('request', (r) => {
		if (r.url().endsWith(`/catalog/tasks/${ownTaskId}/suspend`)) calls++;
	});
	await toggle.click();
	const dialog = page.getByRole('dialog');
	await expect(dialog).toContainText('The Task Manager will not run this task until it is resumed.');
	await expect(dialog).toContainText(`It runs flow ${flowId} on its schedule`);
	await page.screenshot({ path: `${EVIDENCE}/us31-suspend-confirm.png` });
	await dialog.getByRole('button', { name: 'Cancel' }).click();
	await expect(dialog).toHaveCount(0);
	// Escape is a cancel too, from the keyboard (FR-004).
	await toggle.focus();
	await page.keyboard.press('Space');
	await expect(dialog).toBeVisible();
	await page.keyboard.press('Escape');
	await expect(dialog).toHaveCount(0);
	expect(calls).toBe(0);
	await expect(toggle).not.toBeChecked();

	// Confirm: suspended by the platform, the count follows.
	await toggle.click();
	await dialog.getByRole('button', { name: 'Suspend' }).click();
	await expect(toggle).toBeChecked();
	await expect(row(page, ownTaskId).getByTestId('suspended-mark')).toBeVisible();
	await expect(page.getByTestId('count-suspended')).toHaveText(String(before.counts.suspended + 1));

	// A refusal is shown verbatim and the switch keeps the platform's state.
	await page.route(`**/catalog/tasks/${ownTaskId}/suspend`, (route) =>
		route.fulfill({ status: 403, contentType: 'application/json', body: JSON.stringify({ status: 403, title: 'Forbidden', detail: 'ERROR #822: Access Denied' }) }),
	{ times: 1 });
	await toggle.click();
	await dialog.getByRole('button', { name: 'Resume' }).click();
	await expect(pane.getByTestId('action-error')).toHaveText('HTTP 403 — ERROR #822: Access Denied');
	await expect(toggle).toBeChecked();

	// Resume for real.
	await toggle.click();
	await dialog.getByRole('button', { name: 'Resume' }).click();
	await expect(toggle).not.toBeChecked();
	await expect(page.getByTestId('count-suspended')).toHaveText(String(before.counts.suspended));
	expect((await apiTask(page.request, ownTaskId)).view.suspended).toEqual({ kind: 'value', value: false });
});

test('accessibility — the catalog with a detail open, dark and light (SC-008)', async ({ page }) => {
	await signInAt(page, `?view=catalog&task=${ownTaskId}`);
	await expect(detail(page).getByRole('switch')).toBeVisible();
	await page.getByRole('banner').getByRole('button', { name: 'Dark', exact: true }).click();
	await expectNoSeriousA11y(page, 'us31-catalog-dark');
	await page.getByRole('banner').getByRole('button', { name: 'Light', exact: true }).click();
	await expectNoSeriousA11y(page, 'us31-catalog-light');
	await page.screenshot({ path: `${EVIDENCE}/us31-catalog-light.png` });
	await page.getByRole('banner').getByRole('button', { name: 'Dark', exact: true }).click();
});
