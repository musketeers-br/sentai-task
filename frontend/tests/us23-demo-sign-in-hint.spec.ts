import { expect, test } from '@playwright/test';
import { entry } from './support';

// spec 011 User Story 3, scenario 4 (FR-009): the public demo's sign-in screen shows the demo
// account and points at the showcase flow; a normal installation shows nothing extra.
const DEMO = { account: 'sentai-demo', password: 'sentai-demo-2026', showcase: 'Showcase: nightly checks across servers' };

test('us23 — a demo instance shows the demo account and the showcase hint', async ({ page }) => {
	await page.route('**/csp/sentai/demo.json', (route) => route.fulfill({ status: 200, json: DEMO }));
	await page.goto(entry());
	const hint = page.getByTestId('demo-hint');
	await expect(hint).toBeVisible();
	await expect(hint).toContainText('sentai-demo');
	await expect(hint).toContainText('sentai-demo-2026');
	await expect(hint).toContainText(DEMO.showcase);
	await expect(hint).toContainText('Open flow');
});

test('us23 — a normal installation (no demo.json) shows no hint', async ({ page }) => {
	let asked = false;
	await page.route('**/csp/sentai/demo.json', (route) => {
		asked = true;
		return route.fulfill({ status: 404, body: 'Not found' });
	});
	await page.goto(entry());
	await expect(page.getByLabel('User')).toBeVisible();
	await expect.poll(() => asked).toBe(true);
	await expect(page.getByTestId('demo-hint')).toHaveCount(0);
});
