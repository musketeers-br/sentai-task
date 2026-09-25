import { expect, test } from '@playwright/test';

// No unauthenticated web app (HANDOFF constraint): the canvas itself is behind the IRIS
// password. Without it the browser gets a Basic challenge and none of the application.
test('the canvas is not served without the IRIS password', async ({ browser, baseURL }) => {
	// Plain fetch: Playwright's own contexts inherit the configured credentials.
	for (const path of ['', 'index.html', '_app/version.json']) {
		const res = await fetch(new URL(path, baseURL));
		expect(res.status, path).toBe(401);
		expect(res.headers.get('www-authenticate'), path).toBe('Basic');
		expect(await res.text(), path).not.toContain('_app/immutable');
	}

	const wrong = await browser.newContext({ httpCredentials: { username: '_SYSTEM', password: 'wrong' } });
	const page = await wrong.newPage();
	const res = await page.goto(new URL('index.html', baseURL).href);
	expect(res?.status()).toBe(401);
	await expect(page.getByLabel('User')).toHaveCount(0);
	await wrong.close();
});
