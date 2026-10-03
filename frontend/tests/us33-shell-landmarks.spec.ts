import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { runToEnd, seedQuickFlow } from './runs-support';
import { expandPalette, LANDING, signInAt } from './support';

// Spec 023 follow-up — the app shell's accessibility findings and the palette's overflow, closed and
// kept closed. Every screen has exactly one main landmark and one level-one heading, and axe's
// landmark rules pass; no palette entry is wider than its box.

const LANDMARK_RULES = ['landmark-one-main', 'page-has-heading-one', 'region', 'landmark-no-duplicate-main'];

async function expectLandmarks(page: Page, screen: string) {
	await expect(page.locator('main'), `${screen}: one main`).toHaveCount(1);
	await expect(page.locator('h1'), `${screen}: one h1`).toHaveCount(1);
	const result = await new AxeBuilder({ page }).withRules(LANDMARK_RULES).analyze();
	expect(
		result.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`),
		screen
	).toEqual([]);
}

test('every screen has one main landmark and one level-one heading', async ({ page }) => {
	await signInAt(page, LANDING);
	await expect(page.getByRole('heading', { name: 'Overview', level: 1 })).toBeVisible();
	await expectLandmarks(page, 'Overview');

	for (const [tab, ready] of [
		['Flows', page.getByRole('toolbar', { name: 'Flow' })],
		['Task catalog', page.getByRole('heading', { name: 'Task catalog', level: 1 })],
		['Targets', page.getByRole('heading', { name: 'Targets', level: 1 })],
		['Runs', page.getByRole('heading', { name: 'Runs', level: 1 })]
	] as const) {
		await page.getByRole('banner').getByRole('button', { name: tab, exact: true }).click();
		await expect(ready).toBeVisible();
		await expectLandmarks(page, tab);
	}
	// The editor's heading names the flow, for screen readers only.
	await page.getByRole('banner').getByRole('button', { name: 'Flows', exact: true }).click();
	await expect(page.getByRole('heading', { level: 1 })).toHaveText(/^Flows — /);
});

test('the run view has one main landmark and the flow name as its heading', async ({ page, request }) => {
	const name = `us33 landmarks ${Date.now()}`;
	const flowId = await seedQuickFlow(request, name);
	const run = await runToEnd(request, flowId);
	await signInAt(page, `?flow=${flowId}&run=${run.guid}`);
	await expect(page.getByTestId('run-state')).toBeVisible();
	await expect(page.getByRole('heading', { level: 1 })).toHaveText(name);
	await expectLandmarks(page, 'Run view');
});

test('no palette entry is wider than its box (long class names wrap)', async ({ page }) => {
	await signInAt(page, '?view=flows');
	await expandPalette(page);
	const overflowing = await page
		.getByRole('complementary', { name: 'Step types' })
		.locator('[data-step-type]')
		.evaluateAll((entries) =>
			entries
				.filter((e) => e.scrollWidth > e.clientWidth + 1)
				.map((e) => `${e.getAttribute('data-step-type')}: ${e.scrollWidth} > ${e.clientWidth}`)
		);
	expect(overflowing).toEqual([]);
});
