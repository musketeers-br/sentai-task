import { expect, test, type Page, type Route } from '@playwright/test';
import { PASSWORD, seedFlow, signIn, USER } from './support';

// spec 011 User Story 5 — the operator is warned before a cancel that raises a platform alert
// (FR-015…FR-018). Nothing here actually cancels a platform job: the dialogs are answered with
// "Keep running" and the integrity check is left to finish, so the instance raises no alert.

const LIMITATIONS = 'docs/limitations.md#cancel-alert';
const TOOLTIP = 'Asks the instance running this step to stop its job, and marks the step cancelled.';

const node = (page: Page, stepId: string) => page.locator(`.svelte-flow__node[data-id="${stepId}"]`);
const chip = (page: Page, stepId: string) => node(page, stepId).getByTestId('state-chip');
const cancelWave = (page: Page) => page.getByRole('dialog', { name: 'Cancel wave?' });

async function dispatchFromUi(page: Page) {
	await page.getByRole('button', { name: 'Run now' }).click();
	await page.getByLabel(`Password for ${USER}`).fill(PASSWORD);
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
	await expect(page.getByTestId('run-state')).toBeVisible();
}

test('us22 — a running integrity check: Cancel wave and the step Cancel both carry the alert notice', async ({ page, request }) => {
	test.setTimeout(240_000);
	const id = await seedFlow(request, {
		name: `us22-ic ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			{ id: '01', type: 'integrity-check', taskName: 'Integrity check — USER', namespace: 'USER',
			  databaseDirectory: '/usr/irissys/mgr/user/', runAsUser: '', wqmCategory: 'Default', timeoutMinutes: 30 }
		],
		edges: [],
		joins: []
	});
	await signIn(page, `?flow=${id}`);
	await dispatchFromUi(page);
	await expect(chip(page, '01')).toHaveText('RUNNING');

	// (1) Cancel wave: the notice is there, with its link; "Keep running" sends nothing.
	await page.getByRole('button', { name: 'Cancel wave' }).click();
	await expect(cancelWave(page)).toBeVisible();
	const notice = cancelWave(page).getByTestId('cancel-alert-notice');
	await expect(notice).toBeVisible();
	await expect(notice).toContainText('IRIS records a cancelled platform job as an alert');
	await expect(notice.getByRole('link', { name: 'Why' })).toHaveAttribute('href', new RegExp(`${LIMITATIONS}$`));
	await cancelWave(page).getByRole('button', { name: 'Keep running' }).click();
	await expect(cancelWave(page)).toBeHidden();

	// (4) The step's Cancel says what it does now (spec 008 forwards the cancel).
	const cancel = node(page, '01').getByRole('button', { name: 'Cancel' });
	await expect(cancel).toHaveAttribute('title', TOOLTIP);

	// (2) The step's Cancel asks first, with the same notice; "Keep running" leaves it running.
	await cancel.click();
	const confirm = page.getByRole('dialog', { name: 'Cancel step #01?' });
	await expect(confirm).toBeVisible();
	await expect(confirm.getByTestId('cancel-alert-notice')).toContainText('may report "unhealthy"');
	await confirm.getByRole('button', { name: 'Keep running' }).click();
	await expect(confirm).toBeHidden();
	await expect(chip(page, '01')).toHaveText('RUNNING');

	// Let the check finish on its own: no platform job is cancelled, so no alert is raised.
	await expect(chip(page, '01')).toHaveText('COMPLETED', { timeout: 180_000 });
});

test('us22 — in-process steps only: Cancel wave has no notice and the step Cancel does not ask', async ({ page, request }) => {
	const id = await seedFlow(request, {
		name: `us22-inproc ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			{ id: '01', type: 'db-size-report', taskName: 'Database size report', namespace: '%SYS',
			  databaseDirectory: '', runAsUser: '', wqmCategory: 'Default', timeoutMinutes: 10, parameters: {} }
		],
		edges: [],
		joins: []
	});
	// The report ends in about a second; the run read is held at "running" so the dialog can be
	// opened while the step still runs (the UI decides from this read alone).
	await page.route('**/csp/sentai/api/v1/runs/*', async (route: Route) => {
		if (route.request().method() !== 'GET') return route.continue();
		const response = await route.fetch();
		const run = await response.json();
		run.state = 'running';
		run.finishedAt = '';
		for (const step of run.steps) {
			step.state = 'running';
			step.timeFinished = '';
		}
		return route.fulfill({ response, json: run });
	});
	await signIn(page, `?flow=${id}`);
	await dispatchFromUi(page);
	await expect(chip(page, '01')).toHaveText('RUNNING');

	await page.getByRole('button', { name: 'Cancel wave' }).click();
	await expect(cancelWave(page)).toBeVisible();
	await expect(cancelWave(page).getByTestId('cancel-alert-notice')).toHaveCount(0);
	await cancelWave(page).getByRole('button', { name: 'Keep running' }).click();

	// One click, no confirmation: the request goes straight out (intercepted, never sent).
	let cancelled = false;
	await page.route('**/csp/sentai/api/v1/runs/*/steps/*/cancel', (route: Route) => {
		cancelled = true;
		return route.fulfill({ status: 202, json: {} });
	});
	await expect(node(page, '01').getByRole('button', { name: 'Cancel' })).toHaveAttribute('title', TOOLTIP);
	await node(page, '01').getByRole('button', { name: 'Cancel' }).click();
	await expect(page.getByRole('dialog', { name: /Cancel step/ })).toHaveCount(0);
	await expect.poll(() => cancelled).toBe(true);
});
