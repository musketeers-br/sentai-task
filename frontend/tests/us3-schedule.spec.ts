import { writeFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { canonicalFlow, deleteNativeTask, envelope, EVIDENCE_DIR, nativeTaskIds, seedFlow, signIn } from './support';

// spec.md User Story 3 — Schedule (Q5).

/** The canonical graph without the destructive purge: three checks fanning into a journal switch. */
function nonDestructiveFlow(name: string) {
	const flow = canonicalFlow(name);
	return {
		...flow,
		steps: flow.steps.filter((s) => s.id !== '04'),
		edges: [
			{ source: '01', target: '05' },
			{ source: '02', target: '05' },
			{ source: '03', target: '05' }
		],
		joins: [{ target: '05', policy: 'ALL_MUST_SUCCEED' }]
	};
}

test('Q5 — a valid flow compiles into one native Task Manager entry per step', async ({ page, request }) => {
	const id = await seedFlow(request, nonDestructiveFlow(`Q5 schedule ${Date.now()}`));
	try {
		await signIn(page, `?flow=${id}`);

		await page.getByRole('button', { name: 'Validate flow' }).click();
		await expect(page.getByRole('status')).toContainText('Flow is valid');

		await page.getByRole('button', { name: 'Schedule in Task Manager' }).click();
		const dialog = page.getByRole('dialog', { name: 'Schedule in Task Manager' });
		await dialog.getByLabel('Schedule').fill('WEEKLY SAT 03:00');
		await dialog.getByLabel('WQM category').fill('Default');

		const scheduleCall = page.waitForResponse((r) => r.url().endsWith(`/flows/${id}/schedule`));
		await dialog.getByRole('button', { name: 'Schedule', exact: true }).click();
		const response = await scheduleCall;
		const body = await response.json();
		writeFileSync(
			`${EVIDENCE_DIR}/q5-schedule.json`,
			envelope(
				'q5-schedule',
				{
					method: 'POST',
					url_path: `/csp/sentai/api/v1/flows/${id}/schedule`,
					body: JSON.parse(response.request().postData() ?? '{}')
				},
				{ status: response.status(), body },
				[
					'Native tasks were deleted after capture so the dev instance keeps no schedule.',
					'nextRun is the value the backend returns; converting scheduleSpec into %SYS.Task timing is an open backend item (spec 003 HANDOFF).'
				]
			)
		);

		expect(response.status()).toBe(201);
		expect(body.taskIds).toHaveLength(4);
		expect(body.nextRun).toBeTruthy();
		await expect(dialog.getByTestId('schedule-result')).toContainText('Created 4 Task Manager entries');
		expect((await nativeTaskIds(request, id)).sort()).toEqual(body.taskIds.map(Number).sort());
		await dialog.getByRole('button', { name: 'Close' }).click();
	} finally {
		for (const taskId of await nativeTaskIds(request, id)) await deleteNativeTask(request, taskId);
	}
	expect(await nativeTaskIds(request, id)).toEqual([]);
});

test('Q5 — a flow with a destructive step is refused and no native task is created', async ({ page, request }) => {
	const id = await seedFlow(request, canonicalFlow(`Q5 destructive ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	await page.getByRole('button', { name: 'Schedule in Task Manager' }).click();
	const dialog = page.getByRole('dialog', { name: 'Schedule in Task Manager' });
	await dialog.getByRole('button', { name: 'Schedule', exact: true }).click();

	// The platform's own refusal, verbatim, naming the step (Constitution III/IV).
	await expect(dialog.getByTestId('schedule-result')).toContainText(
		"#04 · Step type 'purge-audit-records' is destructive"
	);
	await dialog.getByRole('button', { name: 'Cancel' }).click();
	await expect(page.locator('.svelte-flow__node[data-id="04"]').getByTestId('validation-error')).toContainText(
		'not schedulable in v1'
	);
	await expect(page.getByRole('button', { name: 'Schedule in Task Manager' })).toBeDisabled();
	expect(await nativeTaskIds(request, id)).toEqual([]);
});
