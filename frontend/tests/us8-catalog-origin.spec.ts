/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { apiTask, catalog, detail, expectDetail } from './catalog-support';
import { deleteFlow } from './iris';
import { canonicalFlow, deleteNativeTask, envelope, nativeTaskIds, seedFlow, signInAt, token } from './support';

// spec 007 User Story 2 — Recognise what SentaiTask scheduled and open its flow (FR-009, SC-002).

const EVIDENCE = '../specs/007-canvas-management-screens/evidence';

test('us8-catalog-origin — a scheduled 3-step flow gives 3 marked rows whose link opens the flow', async ({ page }) => {
	const request = page.request;
	const base = canonicalFlow(`us8 origin ${Date.now()}`);
	const flow = { ...base, steps: base.steps.slice(0, 3), edges: [], joins: [], canvasGeometry: { nodes: {} } };
	const flowId = await seedFlow(request, flow);
	let flowDeleted = false;
	try {
		const scheduled = await request.post(`/csp/sentai/api/v1/flows/${flowId}/schedule`, {
			headers: { Authorization: `Bearer ${await token(request)}` },
			data: { scheduleSpec: 'WEEKLY SAT 03:00', category: 'Default' }
		});
		expect(scheduled.status(), await scheduled.text()).toBe(201);

		await signInAt(page, '?view=catalog');
		await page.getByLabel('Search tasks').fill(`SentaiTask: ${flowId}#`);
		const rows = catalog(page).getByTestId('catalog-row');
		await expect(rows).toHaveCount(3);
		for (const step of ['01', '02', '03']) {
			await expect(rows.getByTestId('origin-mark').filter({ hasText: `flow ${flowId} · step ${step}` })).toHaveCount(1);
		}

		// The detail of a SentaiTask task: every field equals the item read.
		const firstId = await rows.first().getAttribute('data-task-id');
		const { wire, view } = await apiTask(request, firstId!);
		await rows.first().click(); // click 1
		await expect(page).toHaveURL(new RegExp(`[?&]task=${firstId}`));
		const shown = await expectDetail(page, view);

		// SC-002: the flow in two clicks.
		await detail(page).getByRole('link', { name: `flow ${flowId} · step ${view.origin!.stepId}` }).click(); // click 2
		await expect(page).toHaveURL(new RegExp(`[?&]flow=${flowId}`));
		await expect(page).not.toHaveURL(/view=catalog/);
		await expect(page.getByLabel('Flow name')).toHaveValue(flow.name);
		await expect(page.locator('.svelte-flow__node')).toHaveCount(3);

		// A deleted flow: the mark says so, and there is no link.
		deleteFlow(flowId);
		flowDeleted = true;
		await page.getByRole('button', { name: 'Task catalog', exact: true }).click();
		await page.getByLabel('Search tasks').fill(`SentaiTask: ${flowId}#`);
		await expect(rows).toHaveCount(3);
		await expect(rows.getByTestId('origin-mark').filter({ hasText: 'flow not found' })).toHaveCount(3);
		await expect(catalog(page).getByRole('link', { name: /flow \d+ · step/ })).toHaveCount(0);

		mkdirSync(EVIDENCE, { recursive: true });
		writeFileSync(
			`${EVIDENCE}/us2-origin.json`,
			envelope('us2-origin', { method: 'GET', path: `/csp/sentai/api/v1/catalog/tasks/${firstId}` }, { status: 200, body: wire }, [
				`Flow ${flowId} (3 integrity checks) scheduled; the catalog search "SentaiTask: ${flowId}#" showed exactly 3 rows marked flow ${flowId} · step 01/02/03.`,
				`Detail shown for task ${firstId}, field by field: ${JSON.stringify(shown)}`,
				'Row click, then the origin link, opened the flow on the canvas (SC-002: 2 clicks).',
				'After the flow was deleted, all 3 rows read "flow not found" with no link. The 3 native tasks and the flow were deleted afterwards.'
			])
		);
	} finally {
		for (const taskId of await nativeTaskIds(request, flowId)) await deleteNativeTask(request, taskId);
		if (!flowDeleted) deleteFlow(flowId);
	}
	expect(await nativeTaskIds(request, flowId)).toEqual([]);
});
