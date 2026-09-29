import { expect, test, type Page, type Route } from '@playwright/test';
import { runToEnd, seedQuickFlow } from './runs-support';
import { signIn, signInAt } from './support';

// spec 012 User Story 2 — find and open past runs (FR-006…FR-012).

const rows = (page: Page) => page.getByTestId('run-row');

test('us25 — newest first, filters in the address, a past run opens read-only and Back returns', async ({ page, request }) => {
	const stamp = Date.now();
	const a = await seedQuickFlow(request, `us25-a ${stamp}`);
	const b = await seedQuickFlow(request, `us25-b ${stamp}`);
	const older = await runToEnd(request, a);
	const newer = await runToEnd(request, a);
	await runToEnd(request, b);

	await signIn(page);
	await page.getByRole('banner').getByRole('button', { name: 'Runs' }).click();
	await expect(rows(page).first()).toContainText(`us25-b ${stamp}`);

	// Filter by flow A: its two runs, newest first; the filter survives a reload (FR-007).
	await page.getByLabel('Flow', { exact: true }).selectOption({ label: `us25-a ${stamp}` });
	await expect(rows(page)).toHaveCount(2);
	await expect(rows(page).first()).toHaveAttribute('data-guid', newer.guid);
	await page.reload();
	await expect(rows(page)).toHaveCount(2);
	await page.getByLabel('Outcome').selectOption('failed');
	await expect(page.getByTestId('runs-empty')).toHaveText('No failed runs for this flow.');
	await page.getByLabel('Outcome').selectOption('completed');
	await expect(rows(page)).toHaveCount(2);

	// Open the older run: read-only, with its log, and Back to runs keeps the filters (FR-009).
	await rows(page).nth(1).getByRole('button').first().click();
	await expect(page.getByTestId('run-guid')).toHaveText(older.guid);
	await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED');
	await expect(page.getByRole('button', { name: 'Pause wave' })).toBeDisabled();
	await expect(page.getByRole('button', { name: 'Cancel wave' })).toBeDisabled();
	await expect(page.getByRole('button', { name: 'Re-run step' })).toHaveCount(0);
	await expect(page.getByTestId('log-line').first()).toContainText('Run dispatched by');
	await page.getByRole('button', { name: 'Back to runs' }).click();
	await expect(page.getByLabel('Flow', { exact: true })).toHaveValue(a);
	await expect(page.getByLabel('Outcome')).toHaveValue('completed');
	await expect(rows(page)).toHaveCount(2);
});

test('us25 — Run history from a flow, paging without duplicates, and the top bar still fits', async ({ page, request }) => {
	const stamp = Date.now();
	const a = await seedQuickFlow(request, `us25-page ${stamp}`);
	const guids = [];
	for (let i = 0; i < 3; i++) guids.push((await runToEnd(request, a)).guid);

	await signIn(page, `?flow=${a}`);
	await page.getByRole('button', { name: 'More' }).click();
	await page.getByRole('menuitem', { name: 'Run history' }).click();
	await expect(page.getByLabel('Flow', { exact: true })).toHaveValue(a);
	await expect(rows(page)).toHaveCount(3);

	// A page of two, then Load more: three distinct runs, newest first (FR-008).
	const url = new URL(page.url());
	url.searchParams.set('pageSize', '2');
	await page.goto(url.toString());
	await expect(rows(page)).toHaveCount(2);
	await page.getByRole('button', { name: 'Load more' }).click();
	await expect(rows(page)).toHaveCount(3);
	const shown = await rows(page).evaluateAll((els) => els.map((e) => e.getAttribute('data-guid')));
	expect(shown).toEqual([...guids].reverse());
	await expect(page.getByRole('button', { name: 'Load more' })).toHaveCount(0);

	// Four tabs and the flow actions still fit at 1440 px (research R-3).
	await page.getByRole('banner').getByRole('button', { name: 'Flows' }).click();
	const fits = await page.evaluate(() => {
		const bar = document.querySelector('header.top-bar') as HTMLElement;
		const box = bar.getBoundingClientRect();
		const clipped = [...bar.querySelectorAll('button, input')]
			.map((el) => ({ el, r: el.getBoundingClientRect() }))
			.filter(({ r }) => r.width > 0 && (r.left < box.left - 0.5 || r.right > box.right + 0.5))
			.map(({ el }) => (el as HTMLElement).innerText || (el as HTMLInputElement).value);
		return { clipped, overflow: bar.scrollWidth - bar.clientWidth };
	});
	expect(fits).toEqual({ clipped: [], overflow: 0 });
});

test('us25 — a refused list shows the platform words, not an empty list (FR-011)', async ({ page }) => {
	await page.route(/\/csp\/sentai\/api\/v1\/runs\?/, (route: Route) =>
		route.fulfill({ status: 403, json: { status: 403, title: 'Forbidden', detail: 'SQLCODE -99: User e2e is not privileged for the operation' } })
	);
	await signInAt(page, '?view=runs');
	await expect(page.getByTestId('runs-refused')).toContainText('SQLCODE -99: User e2e is not privileged for the operation');
	await expect(rows(page)).toHaveCount(0);
});
