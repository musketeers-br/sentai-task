import { expect, test, type Page } from '@playwright/test';
import { deleteFlowWithRuns, recordScheduledStartFailure } from './iris';
import { nativeTaskIds, PASSWORD, seedFlow, signIn, signInAt, unscheduleFlow, USER, v1Flow } from './support';

// spec 015 User Story 4 — the schedule dialog against the real platform (no firing here; the
// acceptance script proves firing): schedule, see, update, renew, refuse, unschedule; history marker.

const dialogOf = (page: Page) => page.getByRole('dialog', { name: 'Schedule in Task Manager' });

async function openDialog(page: Page) {
	await page.getByRole('button', { name: 'Schedule in Task Manager' }).click();
	await expect(dialogOf(page).getByTestId('schedule-instance-time')).toBeVisible();
	return dialogOf(page);
}

test('us28 — schedule, reopen, update, renew, wrong password, unschedule; nothing typed is kept', async ({ page, request }) => {
	const name = `us28-dialog ${Date.now()}`;
	const id = await seedFlow(request, v1Flow(name));
	try {
		await signIn(page, `?flow=${id}`);
		let dialog = await openDialog(page);
		await expect(dialog.getByTestId('schedule-none')).toHaveText('Not scheduled.');
		await expect(dialog.getByTestId('schedule-wallet')).toContainText('IRIS Wallet');
		await expect(dialog.getByLabel('Run as')).toHaveValue(USER);

		// A wrong password: the platform's refusal, on the password field; nothing created.
		await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(`${PASSWORD}-wrong`);
		await dialog.getByRole('button', { name: 'Schedule', exact: true }).click();
		await expect(dialog.getByTestId('schedule-password-error')).toContainText('CREDENTIAL_REFUSED');
		expect(await nativeTaskIds(request, id)).toEqual([]);

		// Schedule daily at 04:00.
		await dialog.getByLabel('At', { exact: true }).fill('04:00');
		await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD);
		await dialog.getByRole('button', { name: 'Schedule', exact: true }).click();
		await expect(dialog.getByTestId('schedule-result')).toContainText('Scheduled: Daily at 04:00');
		const first = await nativeTaskIds(request, id);
		expect(first).toHaveLength(1);
		await dialog.getByRole('button', { name: 'Close' }).click();

		// Reopen: the current schedule, with the platform's next run; the password field is empty.
		dialog = await openDialog(page);
		await expect(dialog.getByTestId('schedule-current')).toContainText('Daily at 04:00');
		await expect(dialog.getByTestId('schedule-next')).toContainText('04:00:00');
		await expect(dialog.getByLabel(`Password for ${USER}`, { exact: true })).toHaveValue('');

		// Update to weekly on Monday: still one task.
		await dialog.getByRole('radio', { name: 'Weekly' }).check();
		await dialog.getByRole('checkbox', { name: 'Sat' }).uncheck();
		await dialog.getByRole('checkbox', { name: 'Mon' }).check();
		await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD);
		await dialog.getByRole('button', { name: 'Update' }).click();
		await expect(dialog.getByTestId('schedule-current')).toContainText('Weekly on Mon at 04:00');
		const second = await nativeTaskIds(request, id);
		expect(second).toHaveLength(1);
		expect(second).not.toEqual(first);

		// Renew credential: same timing, one task.
		await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD);
		await dialog.getByRole('button', { name: 'Renew credential' }).click();
		await expect(dialog.getByTestId('schedule-result')).toContainText('Scheduled: Weekly on Mon at 04:00');
		expect(await nativeTaskIds(request, id)).toHaveLength(1);

		// No password in the browser's storage.
		const stored = await page.evaluate(() => JSON.stringify({ ...sessionStorage, ...localStorage }));
		expect(stored).not.toContain('"password"');
		expect(stored).not.toContain(`${PASSWORD}-wrong`);

		// Unschedule, confirmed.
		await dialog.getByRole('button', { name: 'Unschedule…' }).click();
		await dialog.getByRole('alertdialog', { name: 'Unschedule' }).getByRole('button', { name: 'Unschedule' }).click();
		await expect(dialog.getByTestId('schedule-removed')).toContainText('Unscheduled');
		await expect(dialog.getByTestId('schedule-none')).toBeVisible();
		expect(await nativeTaskIds(request, id)).toEqual([]);
	} finally {
		await unscheduleFlow(request, id);
		deleteFlowWithRuns(id, name);
	}
});

test('us28 — a scheduled run is marked in the history and can be filtered', async ({ page, request }) => {
	const name = `us28-history ${Date.now()}`;
	const id = await seedFlow(request, v1Flow(name));
	try {
		recordScheduledStartFailure(id, name, USER, 'us28 marker');
		await signInAt(page, `?view=runs&runsFlow=${id}&runsTrigger=scheduled`);
		const rows = page.getByTestId('run-row');
		await expect(rows).toHaveCount(1);
		await expect(rows.first().getByTestId('run-trigger')).toHaveText('scheduled');
		await page.getByLabel('Started').selectOption('manual');
		await expect(page.getByTestId('runs-empty')).toBeVisible();
	} finally {
		deleteFlowWithRuns(id, name);
	}
});
