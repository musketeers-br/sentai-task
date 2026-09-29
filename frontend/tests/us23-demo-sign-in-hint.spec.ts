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

test('us23 — a normal installation (the shipped demo.json says demo: false) shows no hint and logs no error', async ({ page }) => {
	// A 404 would be logged as a console error on every sign-in screen; the build ships a neutral
	// file instead, which the public demo's up.sh overwrites.
	const errors: string[] = [];
	page.on('console', (m) => {
		if (m.type() === 'error') errors.push(m.text());
	});
	const answered = page.waitForResponse('**/csp/sentai/demo.json');
	await page.goto(entry());
	expect((await answered).status()).toBe(200);
	await expect(page.getByLabel('User')).toBeVisible();
	await expect(page.getByTestId('demo-hint')).toHaveCount(0);
	expect(errors).toEqual([]);
});
