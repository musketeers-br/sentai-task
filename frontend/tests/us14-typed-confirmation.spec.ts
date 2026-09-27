/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { deleteFlow } from './iris';
import { envelope, PASSWORD, seedFlow, signIn, token, USER } from './support';

// spec 007 User Story 6 / D-7 — the third destructive signal: a typed confirmation per destructive
// step before dispatch (spec 002 FR-013). Runs only under gate G-C: `purge-task-history` made
// available temporarily, uncommitted, on the dev container (spec 007 tasks.md); otherwise skipped.

const EVIDENCE = '../specs/007-canvas-management-screens/evidence';

test('us14-typed-confirmation — a wrong value is refused verbatim (428); the right one dispatches', async ({ page }) => {
	const request = page.request;
	const auth = { Authorization: `Bearer ${await token(request)}` };
	const types = (await (await request.get('/csp/sentai/api/v1/catalog/step-types', { headers: auth })).json()) as Array<{
		type: string;
		available?: boolean;
	}>;
	test.skip(types.find((t) => t.type === 'purge-task-history')?.available !== true, 'gate G-C not held: purge-task-history is not available');

	const flowId = await seedFlow(request, {
		name: `us14 typed confirmation ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			{ id: '01', type: 'purge-task-history', taskName: 'Purge task history', namespace: '%SYS', runAsUser: '', wqmCategory: 'Default', timeoutMinutes: 5 }
		],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	});
	let runGuid = '';
	try {
		await signIn(page, `?flow=${flowId}`);
		await page.getByRole('button', { name: 'Run now' }).click();
		const dialog = page.getByRole('dialog');

		// One required field, naming the step and the value to type.
		const field = dialog.getByLabel('Type %SYS to confirm #01 Purge task history');
		await expect(field).toHaveAttribute('required', '');
		await expect(dialog.getByRole('textbox', { name: /to confirm/ })).toHaveCount(1);

		// A wrong value: the backend's 428 detail, verbatim; the dialog stays open.
		await dialog.getByLabel(`Password for ${USER}`).fill(PASSWORD);
		await field.fill('USER');
		const refusedCall = page.waitForResponse((r) => r.url().endsWith(`/flows/${flowId}/dispatch`));
		await dialog.getByRole('button', { name: 'Dispatch', exact: true }).click();
		const refused = await refusedCall;
		expect(refused.status()).toBe(428);
		const problem = await refused.json();
		await expect(dialog.getByRole('alert')).toContainText(problem.detail);
		await expect(dialog).toBeVisible();

		// The right value dispatches, and the run screen opens.
		await dialog.getByLabel(`Password for ${USER}`).fill(PASSWORD);
		await field.fill('%SYS');
		const acceptedCall = page.waitForResponse((r) => r.url().endsWith(`/flows/${flowId}/dispatch`));
		await dialog.getByRole('button', { name: 'Dispatch', exact: true }).click();
		const accepted = await acceptedCall;
		expect(accepted.status()).toBe(202);
		runGuid = String((await accepted.json()).guid);
		await expect(page).toHaveURL(new RegExp(`[?&]run=${runGuid}`));
		await expect(page.getByTestId('run-state').first()).toBeVisible();

		mkdirSync(EVIDENCE, { recursive: true });
		writeFileSync(
			`${EVIDENCE}/us6-typed-confirmation.json`,
			envelope(
				'us6-typed-confirmation',
				{ method: 'POST', path: `/csp/sentai/api/v1/flows/${flowId}/dispatch`, bodies: [JSON.parse(refused.request().postData() ?? '{}').confirmations, JSON.parse(accepted.request().postData() ?? '{}').confirmations] },
				{ statuses: [refused.status(), accepted.status()], bodies: [problem, { guid: runGuid }] },
				[
					'Gate G-C: purge-task-history was set available: true on the dev container only, uncommitted, for this run, and reverted afterwards.',
					'The dialog asked one typed value for the one destructive step; the wrong value got the 428 detail verbatim and the dialog stayed open.',
					'Only confirmations are shown here: no password or token is recorded.'
				]
			)
		);
	} finally {
		if (runGuid) await request.post(`/csp/sentai/api/v1/runs/${runGuid}/cancel`, { headers: auth, data: {} });
		// A flow with a run is kept, as the us4 runs are (runs reference their flow).
		if (!runGuid) deleteFlow(flowId);
	}
});
