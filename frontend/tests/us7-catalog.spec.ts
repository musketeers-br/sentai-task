/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import {
	fromWireCatalogPage,
	orderByNextRun,
	statusLabel,
	type CatalogTaskView,
	type WireCatalogPage
} from '../src/lib/catalog/catalog';
import { apiTask, catalog, detail, expectDetail, valueText as cellText } from './catalog-support';
import { createOperatorWithoutTaskPrivilege, deleteOperator } from './iris';
import { envelope, seedFlow, signIn, signInAt, submitSignIn, token, v1Flow } from './support';

const EVIDENCE = '../specs/007-canvas-management-screens/evidence';

// spec 007 User Story 1 — See the platform's scheduled tasks (FR-001, FR-002).


test('us7-catalog navigation — reachable from the top bar, addressable, back keeps the open flow', async ({ page }) => {
	const id = await seedFlow(page.request, v1Flow(`us7 navigation ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	const flowsTab = page.getByRole('button', { name: 'Flows', exact: true });
	const catalogTab = page.getByRole('button', { name: 'Task catalog', exact: true });
	await expect(flowsTab).toHaveAttribute('aria-current', 'page');

	// An unsaved edit that must survive the trip to the catalog and back.
	const edited = `us7 unsaved edit ${Date.now()}`;
	await page.getByLabel('Flow name').fill(edited);
	await expect(page.getByTestId('flow-meta')).toContainText('edited');

	await catalogTab.click();
	await expect(page).toHaveURL(/[?&]view=catalog/);
	await expect(catalog(page)).toBeVisible();
	await expect(catalogTab).toHaveAttribute('aria-current', 'page');
	// Flow actions belong to the Flows screen only.
	await expect(page.getByRole('button', { name: 'Run now' })).toHaveCount(0);
	await expect(page.getByLabel('Flow name')).toHaveCount(0);
	// The list comes from the API: a task every instance has.
	await expect(catalog(page).getByText('Integrity Check', { exact: true })).toBeVisible();

	await page.goBack();
	await expect(page).not.toHaveURL(/view=catalog/);
	await expect(page).toHaveURL(new RegExp(`[?&]flow=${id}`));
	await expect(page.getByLabel('Flow name')).toHaveValue(edited);
	await expect(page.getByTestId('flow-meta')).toContainText('edited');

	await page.goForward();
	await expect(catalog(page)).toBeVisible();

	// Flows tab returns to the editor, still with the edit.
	await flowsTab.click();
	await expect(page.getByLabel('Flow name')).toHaveValue(edited);

	// A deep link opens the catalog right after sign-in, and a reload keeps it there
	// (tokens are in memory only, so the reload asks for the sign-in again).
	const fresh = await page.context().newPage();
	await signInAt(fresh, '?view=catalog');
	await expect(catalog(fresh)).toBeVisible();
	await fresh.reload();
	await submitSignIn(fresh);
	await expect(catalog(fresh)).toBeVisible();
	await expect(fresh).toHaveURL(/[?&]view=catalog/);
	await fresh.close();
});

test('us7-catalog values — every row and value equals the API (SC-001); a refused read shows no rows (FR-010)', async ({ page }) => {
	await signInAt(page, '?view=catalog');
	const rows = catalog(page).getByTestId('catalog-row');
	await expect(rows.first()).toBeVisible();

	const res = await page.request.get('/csp/sentai/api/v1/catalog/tasks', {
		headers: { Authorization: `Bearer ${await token(page.request)}` }
	});
	expect(res.status()).toBe(200);
	const wire = (await res.json()) as WireCatalogPage;
	const expected = orderByNextRun(fromWireCatalogPage(wire).items);

	await expect(rows).toHaveCount(expected.length);
	await expect(page.getByTestId('catalog-count')).toHaveText(`${wire.matched} of ${wire.total} tasks`);
	await expect(catalog(page)).toContainText('sorted by next run');
	await expect(page.getByTestId('catalog-freshness')).toHaveText(/^updated \d+ s ago$/);

	const rendered: Array<Record<string, string>> = [];
	for (const [i, task] of expected.entries()) {
		const row = rows.nth(i);
		const cell = (col: string) => row.locator(`[data-col="${col}"]`);
		await expect(row).toHaveAttribute('data-task-id', String(task.taskId));
		await expect(cell('name')).toHaveText(task.name);
		await expect(cell('namespace')).toHaveText(task.namespace);
		await expect(cell('class')).toHaveText(cellText(task.className));
		await expect(cell('nextRun')).toHaveText(cellText(task.nextRun));
		await expect(cell('lastRun')).toHaveText(cellText(task.lastFinished));
		await expect(cell('status')).toHaveText(cellText(task.status, statusLabel));
		await expect(cell('runAsUser')).toHaveText(cellText(task.runAsUser));
		await expectMarks(row.locator('[data-col="marks"]'), task);
		rendered.push({
			taskId: String(task.taskId),
			...Object.fromEntries(
				await Promise.all(
					['name', 'namespace', 'class', 'nextRun', 'lastRun', 'status', 'runAsUser', 'marks'].map(
						async (col) => [col, (await cell(col).innerText()).trim()] as const
					)
				)
			)
		});
	}

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us1-values.json`,
		envelope('us1-values', { method: 'GET', path: '/csp/sentai/api/v1/catalog/tasks' }, { status: 200, body: wire }, [
			`Rendered rows, in display order (orderByNextRun), compared cell by cell with the body: ${JSON.stringify(rendered)}`
		])
	);

	// FR-006 detail: every field equals the item read, for task 4 and a task whose last run left
	// an error text (shown in full, US-1.4).
	const withError = expected.find((t) => t.lastError.kind === 'value' && t.lastError.value !== '' && t.lastError.value !== 'Success');
	const details: Record<string, Record<string, string>> = {};
	for (const taskId of [4, ...(withError ? [withError.taskId] : [])]) {
		await rows.and(page.locator(`[data-task-id="${taskId}"]`)).click();
		await expect(page).toHaveURL(new RegExp(`[?&]task=${taskId}(&|$)`));
		details[taskId] = await expectDetail(page, (await apiTask(page.request, taskId)).view);
	}
	writeFileSync(
		`${EVIDENCE}/us1-details.json`,
		envelope('us1-details', { method: 'GET', path: '/csp/sentai/api/v1/catalog/tasks/{id}' }, { status: 200, body: details }, [
			'Detail pane text per FR-006 field, equal to the item read of each task.'
		])
	);

	// Deep link to a task's detail, and a non-numeric id answered locally with no call.
	const deep = await page.context().newPage();
	await signInAt(deep, '?view=catalog&task=4');
	await expectDetail(deep, (await apiTask(page.request, 4)).view);
	const itemReads: string[] = [];
	deep.on('request', (r) => {
		if (/\/catalog\/tasks\/[^/?]+/.test(r.url())) itemReads.push(r.url());
	});
	await deep.goto('index.html?view=catalog&task=abc');
	await submitSignIn(deep);
	await expect(detail(deep)).toContainText('Task not found');
	expect(itemReads).toEqual([]);
	await deep.close();

	// FR-010: an operator without a task privilege sees the platform's refusal and no rows.
	const operator = createOperatorWithoutTaskPrivilege();
	try {
		const refused = await page.context().newPage();
		await signInAt(refused, '?view=catalog', operator.user, operator.password);
		await expect(catalog(refused).getByTestId('catalog-refusal')).toHaveText('HTTP 403 — no reason given');
		await expect(catalog(refused).getByTestId('catalog-row')).toHaveCount(0);
		await refused.close();
	} finally {
		deleteOperator(operator);
	}
});

async function expectMarks(marks: ReturnType<Page['locator']>, task: CatalogTaskView) {
	const suspended = task.suspended.kind === 'value' && task.suspended.value;
	await expect(marks.getByTestId('suspended-mark')).toHaveCount(suspended ? 1 : 0);
	await expect(marks.getByTestId('suspended-unavailable')).toHaveCount(task.suspended.kind === 'unavailable' ? 1 : 0);
	await expect(marks.getByTestId('destructive-seal')).toHaveCount(task.destructive === 'yes' ? 1 : 0);
	await expect(marks.getByTestId('destructive-unknown')).toHaveCount(task.destructive === 'unknown' ? 1 : 0);
}
