/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { envelope, PASSWORD, signInAt, token, USER } from './support';
import { contrastFailures } from './theming';

// spec 009 User Story 1 — the Targets screen over the spec 008 API. Needs the compose stack's
// iris-target (the demo allowance lets http://iris-target:52773 be registered).

const EVIDENCE = '../specs/009-canvas-distributed-targets/evidence';
const screen = (page: Page) => page.getByRole('region', { name: 'Targets' });
const pane = (page: Page) => page.getByRole('region', { name: 'Target detail' });
/** The shared demo target (spec 008 quickstart); registered here too, so us15 runs alone and in any order. */
const TARGET = 'iris-target';

async function api(page: Page, method: string, path: string, data?: object, headers: Record<string, string> = {}) {
	const res = await page.request.fetch(`/csp/sentai/api/v1${path}`, {
		method,
		headers: { Authorization: `Bearer ${await token(page.request)}`, ...headers },
		...(data ? { data } : {})
	});
	return { status: res.status(), body: res.status() === 204 ? null : await res.json() };
}

test.beforeAll(async ({ browser }) => {
	const page = await browser.newPage({ baseURL: test.info().project.use.baseURL });
	if ((await api(page, 'GET', `/targets/${TARGET}`)).status === 404) {
		expect((await api(page, 'POST', '/targets', { name: TARGET, baseUrl: 'http://iris-target:52773', description: 'demo target (compose)' })).status).toBe(201);
	}
	await api(page, 'POST', `/targets/${TARGET}/online`, { online: true });
	await page.close();
});

test('us15-targets — register, read the live state, refusals verbatim, online toggle, delete', async ({ page }) => {
	const name = `e2e-t-${Date.now().toString(36)}`;
	const lost = `${name}-lost`;
	try {
		await signInAt(page, '?view=targets');
		await expect(screen(page)).toBeVisible();

		// Add: the list then equals the API.
		await screen(page).getByRole('button', { name: 'Add target' }).click();
		await pane(page).getByLabel('Name').fill(name);
		await pane(page).getByLabel('Address').fill('http://iris-target:52773');
		await pane(page).getByLabel('Description').fill('e2e target');
		await pane(page).getByRole('button', { name: 'Save target' }).click();
		const row = screen(page).locator(`[data-testid="target-row"][data-name="${name}"]`);
		await expect(row).toBeVisible();
		const listed = (await api(page, 'GET', '/targets')).body as Array<{ name: string; baseUrl: string; online: boolean }>;
		await expect(screen(page).getByTestId('target-row')).toHaveCount(listed.length);
		await expect(row.locator('[data-col="address"]')).toHaveText('http://iris-target:52773');
		await expect(row.locator('[data-col="online"]')).toHaveText('online');

		// A refused address: the API's text, verbatim; nothing added.
		await screen(page).getByRole('button', { name: 'Add target' }).click();
		await pane(page).getByLabel('Name').fill(`${name}-bad`);
		await pane(page).getByLabel('Address').fill('iris-target:52773');
		await pane(page).getByRole('button', { name: 'Save target' }).click();
		await expect(pane(page).getByTestId('target-error')).toHaveText(
			'HTTP 400 — INVALID_TARGET: baseUrl must be scheme://host:port (http or https), with no path, query or user info'
		);
		await expect(screen(page).locator(`[data-name="${name}-bad"]`)).toHaveCount(0);

		// Live state after signing in: every value equals the API's status read.
		await row.click();
		await expect(page).toHaveURL(new RegExp(`[?&]target=${name}`));
		await pane(page).getByLabel(`Password for ${USER} on ${name}`).fill(PASSWORD);
		await pane(page).getByRole('button', { name: 'Read state' }).click();
		const status = pane(page).getByTestId('target-status');
		await expect(status.getByTestId('status-reachable')).toHaveText('reachable');
		const signed = (await api(page, 'POST', `/targets/${name}/sign-in`, { user: USER, password: PASSWORD })).body;
		const read = (await api(page, 'GET', `/targets/${name}/status`, undefined, { 'X-Sentai-Target-Authorization': `Bearer ${signed.accessToken}` })).body;
		await expect(status.getByTestId('status-version')).toHaveText(read.version);
		await expect(status.getByTestId('status-user')).toHaveText(read.user);
		await expect(status.getByTestId('target-category')).toHaveCount(read.categories.length);
		for (const [i, c] of read.categories.entries()) {
			await expect(status.getByTestId('target-category').nth(i)).toContainText(String(c.Name));
		}
		await expect(pane(page).getByLabel(`Password for ${USER} on ${name}`)).toHaveValue('');

		// A wrong password: the target's refusal verbatim, no state.
		await pane(page).getByLabel(`Password for ${USER} on ${name}`).fill('not-the-password');
		await pane(page).getByRole('button', { name: 'Read state' }).click();
		await expect(pane(page).getByTestId('target-signin-error')).toHaveText('HTTP 401 — no reason given');

		// Offline, then online again, confirmed by the API each time.
		await pane(page).getByRole('button', { name: 'Set offline' }).click();
		await expect(row.locator('[data-col="online"]')).toHaveText('offline');
		expect((await api(page, 'GET', `/targets/${name}`)).body.online).toBe(false);
		await pane(page).getByRole('button', { name: 'Set online' }).click();
		await expect(row.locator('[data-col="online"]')).toHaveText('online');

		// A target that does not exist on the network: the sign-in's 502, verbatim.
		expect((await api(page, 'POST', '/targets', { name: lost, baseUrl: 'http://iris-nowhere:52773' })).status).toBe(201);
		await page.getByRole('button', { name: 'Targets', exact: true }).click();
		await screen(page).getByRole('button', { name: 'Refresh' }).click();
		await screen(page).locator(`[data-testid="target-row"][data-name="${lost}"]`).click();
		await pane(page).getByLabel(`Password for ${USER} on ${lost}`).fill(PASSWORD);
		await pane(page).getByRole('button', { name: 'Read state' }).click();
		await expect(pane(page).getByTestId('target-signin-error')).toContainText('HTTP 502 — TARGET_UNREACHABLE: ERROR #6059', { timeout: 30_000 });

		// Delete, with a confirmation.
		await screen(page).locator(`[data-testid="target-row"][data-name="${name}"]`).click();
		await pane(page).getByRole('button', { name: 'Delete target' }).click();
		await pane(page).getByRole('button', { name: `Delete ${name}` }).click();
		await expect(screen(page).locator(`[data-name="${name}"]`)).toHaveCount(0);
		expect((await api(page, 'GET', `/targets/${name}`)).status).toBe(404);

		mkdirSync(EVIDENCE, { recursive: true });
		writeFileSync(
			`${EVIDENCE}/us1-targets.json`,
			envelope('us1-targets', { method: 'GET', path: `/targets/${name}/status` }, { status: 200, body: read }, [
				'Targets screen values compared with GET /targets and GET /targets/{name}/status (reachable, version, user, categories).',
				'Refusals shown verbatim: INVALID_TARGET (400), wrong target password (401), unknown host (502 TARGET_UNREACHABLE).',
				'No token or password is recorded.'
			])
		);
	} finally {
		await api(page, 'DELETE', `/targets/${name}`);
		await api(page, 'DELETE', `/targets/${lost}`);
	}
});

test('us15-targets theming and secrets — both themes read the same; no credential left in the browser', async ({ page }) => {
	await signInAt(page, `?view=targets&target=${TARGET}`);
	await pane(page).getByLabel(`Password for ${USER} on ${TARGET}`).fill(PASSWORD);
	// The target's own tokens, as the page's sign-in to it received them (checked below).
	const targetSignIn = page.waitForResponse((r) => r.url().endsWith(`/targets/${TARGET}/sign-in`) && r.request().method() === 'POST');
	await pane(page).getByRole('button', { name: 'Read state' }).click();
	const targetTokens = (await (await targetSignIn).json()) as { accessToken: string; refreshToken: string };
	expect(targetTokens.accessToken).toMatch(/^eyJ/);
	expect(targetTokens.refreshToken).toMatch(/^eyJ/);
	await expect(pane(page).getByTestId('status-reachable')).toHaveText('reachable');

	mkdirSync(EVIDENCE, { recursive: true });
	const texts: Record<string, string[]> = {};
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', theme.toLowerCase());
		await page.mouse.move(0, 0);
		expect(await contrastFailures(page), `${theme}: every text >= 4.5:1`).toEqual([]);
		texts[theme] = (await page.evaluate(() => document.body.innerText)).split('\n').map((s) => s.trim()).filter(Boolean);
		await page.screenshot({ path: `${EVIDENCE}/sc006-targets-${theme.toLowerCase()}.png` });
	}
	expect(texts.Light).toEqual(texts.Dark);

	// SC-004 (spec 009): nothing about the target sign-in is kept by the browser.
	const stores = await page.evaluate(() => ({ local: { ...localStorage }, session: { ...sessionStorage }, cookies: document.cookie, url: location.href }));
	const kept = JSON.stringify(stores);
	if (PASSWORD.length > 3) expect(kept).not.toContain(PASSWORD);
	// The target's real tokens are nowhere.
	expect(kept.includes(targetTokens.accessToken), 'target access token kept').toBe(false);
	expect(kept.includes(targetTokens.refreshToken), 'target refresh token kept').toBe(false);
	// Exactly one JWT may be kept: this tab's own sign-in to the primary (spec 010 FR-011,
	// sessionStorage["sentai.signin"].refreshToken). Any other token still fails.
	const ownRefresh = (JSON.parse(stores.session['sentai.signin'] ?? '{}') as { refreshToken?: string }).refreshToken;
	expect(ownRefresh, "this tab's kept sign-in").toMatch(/^eyJ/);
	const jwts = kept.match(/eyJ[A-Za-z0-9_-]{10,}(\.[A-Za-z0-9_-]+)*/g) ?? [];
	expect(jwts, 'the only JWT kept is sentai.signin.refreshToken').toEqual([ownRefresh]);
});
