/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { apiTask, catalog, detail } from './catalog-support';
import { createOperatorWithoutTaskPrivilege, deleteFlow, deleteOperator } from './iris';
import { canonicalFlow, deleteNativeTask, envelope, nativeTaskIds, seedFlow, signInAt, token } from './support';

// spec 007 User Story 4 — Suspend and resume a task (FR-008, FR-011). Always on a task this test
// scheduled itself, never on one of the instance's own tasks.

const EVIDENCE = '../specs/007-canvas-management-screens/evidence';

let flowId = '';
let taskId = 0;

test.beforeAll(async ({ request }) => {
	const base = canonicalFlow(`us10 suspend ${Date.now()}`);
	flowId = await seedFlow(request, { ...base, steps: base.steps.slice(0, 1), edges: [], joins: [], canvasGeometry: { nodes: {} } });
	const res = await request.post(`/csp/sentai/api/v1/flows/${flowId}/schedule`, {
		headers: { Authorization: `Bearer ${await token(request)}` },
		data: { scheduleSpec: 'WEEKLY SAT 03:00', category: 'Default' }
	});
	expect(res.status(), await res.text()).toBe(201);
	taskId = Number((await res.json()).taskIds[0]);
});

test.afterAll(async ({ request }) => {
	for (const id of await nativeTaskIds(request, flowId)) await deleteNativeTask(request, id);
	deleteFlow(flowId);
	expect(await nativeTaskIds(request, flowId)).toEqual([]);
});

/** Holds the next suspend call for a moment, so the pending state can be observed. */
async function slowSuspendCall(page: Page) {
	await page.route(`**/catalog/tasks/${taskId}/suspend`, async (route) => {
		await new Promise((r) => setTimeout(r, 600));
		await route.continue();
	}, { times: 1 });
}

test('us10-catalog-suspend — Suspend then Resume, each confirmed by a fresh read', async ({ page }) => {
	await signInAt(page, `?view=catalog&task=${taskId}`);
	const pane = detail(page);
	const row = catalog(page).locator(`[data-testid="catalog-row"][data-task-id="${taskId}"]`);
	await expect(pane.getByTestId('detail-field-suspended')).toHaveText('no');
	await expect(pane.getByRole('button', { name: 'Resume' })).toHaveCount(0);

	await slowSuspendCall(page);
	const suspendCall = page.waitForResponse((r) => r.url().endsWith(`/catalog/tasks/${taskId}/suspend`));
	await pane.getByRole('button', { name: 'Suspend' }).click();
	await expect(pane.getByRole('button', { name: /Suspend/ })).toBeDisabled();
	const suspended = await suspendCall;
	expect(suspended.status()).toBe(200);
	await expect(pane.getByTestId('detail-field-suspended')).toHaveText('yes');
	await expect(row.getByTestId('suspended-mark')).toBeVisible();
	expect((await apiTask(page.request, taskId)).view.suspended).toEqual({ kind: 'value', value: true });

	await slowSuspendCall(page);
	const resumeCall = page.waitForResponse((r) => r.url().endsWith(`/catalog/tasks/${taskId}/suspend`));
	await pane.getByRole('button', { name: 'Resume' }).click();
	await expect(pane.getByRole('button', { name: /Resum/ })).toBeDisabled();
	const resumed = await resumeCall;
	expect(resumed.status()).toBe(200);
	await expect(pane.getByTestId('detail-field-suspended')).toHaveText('no');
	await expect(row.getByTestId('suspended-mark')).toHaveCount(0);
	expect((await apiTask(page.request, taskId)).view.suspended).toEqual({ kind: 'value', value: false });

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us4-suspend.json`,
		envelope(
			'us4-suspend',
			{ method: 'POST', path: `/csp/sentai/api/v1/catalog/tasks/${taskId}/suspend`, bodies: [{ suspended: true }, { suspended: false }] },
			{ statuses: [suspended.status(), resumed.status()], bodies: [await suspended.json(), await resumed.json()] },
			[
				`Task ${taskId} was created by scheduling test flow ${flowId}; it and the flow were deleted afterwards.`,
				'Each button was disabled while its call was pending; detail and row then showed the state in the answer, and a fresh GET agreed.'
			]
		)
	);
});

test('us10-catalog-suspend — an operator without a task privilege sees the refusal verbatim', async ({ page }) => {
	const operator = createOperatorWithoutTaskPrivilege();
	try {
		await signInAt(page, `?view=catalog&task=${taskId}`, operator.user, operator.password);
		await expect(detail(page)).toContainText('HTTP 403 — no reason given');
		await expect(detail(page).getByRole('button', { name: /Suspend|Resume/ })).toHaveCount(0);
	} finally {
		deleteOperator(operator);
	}
});
