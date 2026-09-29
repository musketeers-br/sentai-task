import { expect, test, type Page, type Route } from '@playwright/test';
import { failingFlow, runToEnd, seedQuickFlow } from './runs-support';
import { signInAt as signIn, USER } from './support';

// spec 012 User Story 1 — the run log tells what happened, in order (FR-001…FR-005).

const lines = (page: Page) => page.getByTestId('run-log').getByTestId('log-line');

test('us24 — a finished run reads from dispatch to outcome, oldest first', async ({ page, request }) => {
	const id = await seedQuickFlow(request, `us24-ok ${Date.now()}`);
	const run = await runToEnd(request, id);
	expect(run.state).toBe('completed');
	await signIn(page, `?flow=${id}&run=${run.guid}`);
	await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED');

	const text = await lines(page).allInnerTexts();
	expect(text[0]).toMatch(new RegExp(`^INFO\\s+\\d\\d:\\d\\d:\\d\\d · Run dispatched by ${USER} \\(flow revision 1, 2 steps\\)$`));
	expect(text.some((l) => /#01 Storage headroom started on local/.test(l))).toBe(true);
	expect(text.some((l) => /#02 Database sizes started on local/.test(l))).toBe(true);
	expect(text.some((l) => /#01 completed in \d\d:\d\d/.test(l))).toBe(true);
	expect(text.at(-1)).toMatch(/^INFO\s+.* · Run completed: 2 completed, 0 failed, 0 cancelled \(\d\d:\d\d\)$/);
});

test('us24 — a failure shows the step reason verbatim and the join that stopped the next step', async ({ page, request }) => {
	const id = await seedQuickFlow(request, `us24-fail ${Date.now()}`, failingFlow(`us24-fail ${Date.now()}`));
	const run = await runToEnd(request, id);
	expect(run.state).toBe('failed');
	await signIn(page, `?flow=${id}&run=${run.guid}`);
	await expect(page.getByTestId('run-state')).toContainText('RUN FAILED');

	const failed = lines(page).filter({ hasText: '#01 failed after' });
	await expect(failed).toHaveCount(1);
	await expect(failed).toContainText('ERROR');
	await expect(failed).toHaveClass(/error/);
	// The step's own reason, as the node shows it, appears in the log in quotes.
	const reason = (await page.locator('.svelte-flow__node[data-id="01"]').getByTestId('failure-reason').locator('pre').innerText()).trim();
	await expect(failed).toContainText(`"${reason}"`);
	await expect(lines(page).filter({ hasText: '#02 not started: input #01 failed (all inputs must succeed)' })).toHaveCount(1);
	await expect(lines(page).last()).toContainText('Run failed: 0 completed, 2 failed, 0 cancelled');
});

test('us24 — a run from before the log existed says so', async ({ page, request }) => {
	const id = await seedQuickFlow(request, `us24-old ${Date.now()}`);
	const run = await runToEnd(request, id);
	await page.route(`**/csp/sentai/api/v1/runs/${run.guid}`, async (route: Route) => {
		const response = await route.fetch();
		const body = await response.json();
		body.log = [];
		return route.fulfill({ response, json: body });
	});
	await signIn(page, `?flow=${id}&run=${run.guid}`);
	await expect(page.getByTestId('run-log')).toContainText('No log was recorded for runs before this version.');
});
