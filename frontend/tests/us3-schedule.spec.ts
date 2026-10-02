import { writeFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { canonicalFlow, envelope, EVIDENCE_DIR, flowButton, nativeTaskIds, PASSWORD, seedFlow, signIn, unscheduleFlow, USER, v1Flow } from './support';

// spec.md User Story 3 — Schedule (Q5). Spec 015: one native Task Manager task per flow, running as
// a run-as account whose password is checked and kept only in the IRIS Wallet; scheduled runs run.

test('Q5 — a valid flow is scheduled as one native Task Manager task', async ({ page, request }) => {
	const id = await seedFlow(request, v1Flow(`Q5 schedule ${Date.now()}`));
	try {
		await signIn(page, `?flow=${id}`);

		await flowButton(page, 'validate').click();
		await expect(page.getByRole('status')).toContainText('Flow is valid');

		await flowButton(page, 'schedule').click();
		const dialog = page.getByRole('dialog', { name: 'Schedule in Task Manager' });
		await expect(dialog.getByTestId('schedule-none')).toBeVisible();
		await expect(dialog.getByText('cannot authenticate')).toHaveCount(0);
		await dialog.getByRole('radio', { name: 'Weekly' }).check();
		await expect(dialog.getByTestId('schedule-describe')).toHaveText('Weekly on Sat at 03:00');
		await expect(dialog.getByLabel('Run as')).toHaveValue(USER);
		await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD);

		const scheduleCall = page.waitForResponse((r) => r.url().endsWith(`/flows/${id}/schedule`) && r.request().method() === 'POST');
		await dialog.getByRole('button', { name: 'Schedule', exact: true }).click();
		const response = await scheduleCall;
		const body = await response.json();
		const sent = JSON.parse(response.request().postData() ?? '{}');
		writeFileSync(
			`${EVIDENCE_DIR}/q5-schedule.json`,
			envelope(
				'q5-schedule',
				{ method: 'POST', url_path: `/csp/sentai/api/v1/flows/${id}/schedule`, body: { ...sent, password: '<redacted>' } },
				{ status: response.status(), body },
				['Spec 015: one task per flow, run as the run-as account; the password is kept only in the IRIS Wallet.', 'The task and the stored credential were removed after capture.']
			)
		);

		expect(response.status()).toBe(201);
		expect(await nativeTaskIds(request, id)).toEqual([body.taskId]);
		await expect(dialog.getByTestId('schedule-result')).toContainText('Scheduled: Weekly on Sat at 03:00');
		await expect(dialog.getByTestId('schedule-current')).toContainText('Weekly on Sat at 03:00');
		await dialog.getByRole('button', { name: 'Close' }).click();
	} finally {
		await unscheduleFlow(request, id);
	}
	expect(await nativeTaskIds(request, id)).toEqual([]);
});

test('Q5 — a flow with a destructive step is refused and no native task is created', async ({ page, request }) => {
	const id = await seedFlow(request, canonicalFlow(`Q5 destructive ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	await flowButton(page, 'schedule').click();
	const dialog = page.getByRole('dialog', { name: 'Schedule in Task Manager' });
	await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD);
	await dialog.getByRole('button', { name: 'Schedule', exact: true }).click();

	// The platform's own refusal, verbatim, naming the step (Constitution III/IV).
	await expect(dialog.getByTestId('schedule-result')).toContainText("#04 · Step type 'purge-audit-records' is destructive");
	await dialog.getByRole('button', { name: 'Close' }).click();
	await expect(page.locator('.svelte-flow__node[data-id="04"]').getByTestId('validation-error')).toContainText('not schedulable in v1');
	await expect(flowButton(page, 'schedule')).toBeDisabled();
	expect(await nativeTaskIds(request, id)).toEqual([]);
});
