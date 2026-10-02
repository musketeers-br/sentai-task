/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { dismissGuide, entry, flowButton, paletteEntry, PASSWORD, seedFlow, signIn, signInAt, submitSignIn, token, USER } from './support';

// spec 010 User Story 3 — A reload keeps the operator signed in (FR-009…FR-014, SC-003, SC-007).

const EVIDENCE = '../specs/010-canvas-onboarding-usability/evidence';
const KEPT = 'sentai.signin';
const ENDED = 'Your session ended — sign in again.';

function oneStepFlow(name: string) {
	return {
		name,
		defaultCategory: 'Default',
		steps: [{ id: '01', type: 'db-size-report', taskName: 'Sizes', namespace: '%SYS', wqmCategory: 'Default' }],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	};
}

type Kept = { v: number; refreshToken: string; live: boolean } | null;
const kept = (page: Page): Promise<Kept> =>
	page.evaluate((key) => {
		const raw = sessionStorage.getItem(key);
		return raw ? JSON.parse(raw) : null;
	}, KEPT);
const writeKept = (page: Page, value: Kept) =>
	page.evaluate(([key, v]) => sessionStorage.setItem(key as string, JSON.stringify(v)), [KEPT, value] as const);

const signInForm = (page: Page) => page.getByLabel('User');
const flowName = (page: Page) => page.getByLabel('Flow name');
const flowIdIn = (page: Page) => new URL(page.url()).searchParams.get('flow');

test('us19 reload ×10 over a renewal — the sign-in form never appears and the same flow is open (SC-003)', async ({ page }) => {
	test.slow();
	const name = `us19-reload-${Date.now()}`;
	const id = await seedFlow(page.request, oneStepFlow(name));

	// Counts every appearance of the sign-in form, across documents (research R-3.4: "restoring").
	await page.addInitScript(() => {
		let seen = false;
		new MutationObserver(() => {
			if (!seen && document.getElementById('user')) {
				seen = true;
				sessionStorage.setItem('e2e.signInSeen', String(Number(sessionStorage.getItem('e2e.signInSeen') ?? '0') + 1));
			}
		}).observe(document, { childList: true, subtree: true });
	});
	await signIn(page, `?flow=${id}`);
	await page.evaluate(() => sessionStorage.setItem('e2e.signInSeen', '0'));
	const firstToken = (await kept(page))!.refreshToken;

	for (let i = 0; i < 10; i++) {
		await page.waitForTimeout(7_000); // 10 × 7 s > 60 s: at least one proactive renewal in between
		await page.reload();
		await expect(flowName(page)).toHaveValue(name);
		expect(flowIdIn(page)).toBe(id);
	}
	expect(await page.evaluate(() => sessionStorage.getItem('e2e.signInSeen'))).toBe('0');
	expect((await kept(page))!.refreshToken).not.toBe(firstToken);
});

test('us19 run view — a reload returns to the same live run (scenario 3.2)', async ({ page }) => {
	const id = await seedFlow(page.request, oneStepFlow(`us19-run-${Date.now()}`));
	await signIn(page, `?flow=${id}`);
	await page.getByRole('button', { name: 'Run now' }).click();
	await page.getByLabel(`Password for ${USER}`).fill(PASSWORD);
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
	await expect(page.getByTestId('run-state')).toBeVisible();
	const run = new URL(page.url()).searchParams.get('run');
	expect(run).toBeTruthy();

	await page.reload();
	await expect(page.getByTestId('run-state')).toBeVisible();
	await expect(signInForm(page)).toHaveCount(0);
	expect(new URL(page.url()).searchParams.get('run')).toBe(run);
});

test('us19 sign-out and a new tab — both need a sign-in; nothing usable is left (scenarios 3.3, 3.4, SC-007)', async ({ page, context }) => {
	const id = await seedFlow(page.request, oneStepFlow(`us19-out-${Date.now()}`));
	await signIn(page, `?flow=${id}`);
	expect(await kept(page)).not.toBeNull();

	// A new tab of the same browser does not inherit the tab's sign-in.
	const other = await context.newPage();
	await dismissGuide(other);
	await other.goto(entry(`?flow=${id}`));
	await expect(signInForm(other)).toBeVisible();
	expect(await kept(other)).toBeNull();
	await other.close();

	await page.getByRole('button', { name: 'Sign out' }).click();
	await expect(signInForm(page)).toBeVisible();
	expect(await kept(page)).toBeNull();
	await page.reload();
	await expect(signInForm(page)).toBeVisible();
	expect(await kept(page)).toBeNull();
});

test('us19 duplicated tab — the copy never replays the copied token and signs in on its own (FR-013)', async ({ page, context }) => {
	test.slow();
	const id = await seedFlow(page.request, oneStepFlow(`us19-dup-${Date.now()}`));
	await signIn(page, `?flow=${id}`);
	const copied = await kept(page);
	expect(copied?.live).toBe(true);

	// A duplicated tab starts with a copy of the original's sessionStorage.
	const copy = await context.newPage();
	const refreshes: string[] = [];
	copy.on('request', (r) => {
		if (r.url().includes('/api/admin/refresh')) refreshes.push(r.postData() ?? '');
	});
	await dismissGuide(copy);
	await copy.addInitScript(
		([key, value]) => {
			if (!sessionStorage.getItem('e2e.copied')) {
				sessionStorage.setItem('e2e.copied', '1');
				sessionStorage.setItem(key, value);
			}
		},
		[KEPT, JSON.stringify(copied)] as const
	);
	await copy.goto(entry(`?flow=${id}`));
	await expect(copy.getByText('Sign in to continue in this tab.')).toBeVisible();
	await expect(signInForm(copy)).toBeVisible();
	expect(refreshes).toEqual([]);
	expect(await kept(copy)).toBeNull();

	await submitSignIn(copy);
	await expect(flowName(copy)).toBeVisible();

	// Both renew on their own for more than a minute; neither signs the other out.
	await page.waitForTimeout(70_000);
	for (const p of [page, copy]) {
		await expect(p.getByText('Your session could not be renewed')).toHaveCount(0);
		await flowButton(p, 'open').click();
		await expect(p.getByRole('dialog', { name: 'Open flow' }).getByTestId('flow-count')).toBeVisible();
		await p.keyboard.press('Escape');
	}
	expect((await kept(page))!.refreshToken).not.toBe((await kept(copy))!.refreshToken);
	await copy.close();
});

test('us19 session ended — a refused kept sign-in explains itself, then restores the address (FR-012)', async ({ page }) => {
	test.slow();
	const name = `us19-ended-${Date.now()}`;
	const id = await seedFlow(page.request, oneStepFlow(name));
	await signIn(page, `?flow=${id}`);

	// A token the platform already rotated away (it revokes the previous one on refresh).
	const before = (await kept(page))!.refreshToken;
	await expect.poll(async () => (await kept(page))!.refreshToken, { timeout: 60_000 }).not.toBe(before);
	await writeKept(page, { v: 1, refreshToken: before, live: true });
	await page.reload();
	await expect(page.getByText(ENDED)).toBeVisible();
	await expect(signInForm(page)).toBeVisible();
	expect(await kept(page)).toBeNull();
	await submitSignIn(page);
	await expect(flowName(page)).toHaveValue(name);
	expect(flowIdIn(page)).toBe(id);

	// The screen and the run in the address are restored the same way.
	await page.goto(entry('?view=catalog'));
	await expect(page.getByRole('banner')).toBeVisible();
	await writeKept(page, { v: 1, refreshToken: 'not-a-token', live: false });
	await page.reload();
	await expect(page.getByText(ENDED)).toBeVisible();
	await submitSignIn(page);
	await expect(page.getByRole('button', { name: 'Task catalog' })).toHaveAttribute('aria-current', 'page');
	expect(new URL(page.url()).searchParams.get('view')).toBe('catalog');
});

test('us19 bfcache — pagehide hands the token over and pageshow takes it back (research R-3.3)', async ({ page }) => {
	const name = `us19-bf-${Date.now()}`;
	const id = await seedFlow(page.request, oneStepFlow(name));
	await signIn(page, `?flow=${id}`);
	const refreshes: string[] = [];
	page.on('request', (r) => {
		if (r.url().includes('/api/admin/refresh')) refreshes.push(r.url());
	});

	// Deterministic: the page's own handlers, driven by the events the browser would send.
	const token1 = (await kept(page))!.refreshToken;
	await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })));
	expect(await kept(page)).toEqual({ v: 1, refreshToken: token1, live: false });
	await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
	expect(await kept(page)).toEqual({ v: 1, refreshToken: token1, live: true });
	expect(refreshes).toEqual([]);

	// Real navigation: whichever path the browser takes (bfcache or a new load), the flow is back.
	await page.goto('about:blank');
	await page.goBack();
	await expect(flowName(page)).toHaveValue(name);
	await expect(signInForm(page)).toHaveCount(0);
	expect((await kept(page))!.live).toBe(true);
});

test('us19 storage audit — only the refresh token and its flag are kept; no password, access token or permission (FR-011)', async ({ page }) => {
	let access = '';
	page.on('request', (r) => {
		const auth = r.headers()['authorization'];
		if (r.url().includes('/csp/sentai/api/v1/') && auth?.startsWith('Bearer ')) access = auth.slice(7);
	});
	await signIn(page);
	await expect.poll(() => access).not.toBe('');

	const dump = await page.evaluate(() => ({
		session: Object.fromEntries(Object.entries(sessionStorage)),
		local: Object.fromEntries(Object.entries(localStorage))
	}));
	expect(Object.keys(dump.session)).toEqual([KEPT]);
	expect(Object.keys(JSON.parse(dump.session[KEPT])).sort()).toEqual(['live', 'refreshToken', 'v']);
	for (const key of Object.keys(dump.local)) expect(['sentai.theme', 'sentai.guide.dismissed']).toContain(key);
	const everything = JSON.stringify(dump);
	for (const secret of [PASSWORD, access, USER, 'role', 'permission']) {
		expect(everything.includes(secret), `storage must not contain ${secret === PASSWORD ? 'the password' : secret === access ? 'the access token' : secret}`).toBe(false);
	}

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us19-storage-keys.json`,
		JSON.stringify(
			{
				captured_at: new Date().toISOString(),
				sessionStorage: Object.keys(dump.session),
				[`sessionStorage["${KEPT}"] keys`]: Object.keys(JSON.parse(dump.session[KEPT])).sort(),
				localStorage: Object.keys(dump.local),
				notes: ['Key names only. No value contained the password, the access token, the user name, a role or a permission.']
			},
			null,
			2
		)
	);
});

test('us19 reload during a save — the canvas shows the last revision the server confirmed (edge case)', async ({ page }) => {
	const name = `us19-inflight-${Date.now()}`;
	const id = await seedFlow(page.request, oneStepFlow(name));
	await signIn(page, `?flow=${id}`);
	await (await paletteEntry(page, 'db-size-report')).click();

	let held = false;
	await page.route(
		(url) => url.pathname.endsWith(`/csp/sentai/api/v1/flows/${id}`),
		(route) => {
			if (route.request().method() === 'PUT') held = true; // never continued: the server never sees it
			else void route.continue();
		}
	);
	await flowButton(page, 'save').click();
	await expect.poll(() => held).toBe(true);
	// The route stays: unrouting would release the held PUT to the server. The reload drops it.
	await page.reload();

	await expect(flowName(page)).toHaveValue(name);
	await expect(signInForm(page)).toHaveCount(0);
	await expect(page.getByTestId('flow-meta')).toContainText('rev 1');
	await expect(page.locator('.svelte-flow__node')).toHaveCount(1);
	const res = await page.request.get(`/csp/sentai/api/v1/flows/${id}`, { headers: { Authorization: `Bearer ${await token(page.request)}` } });
	expect(Number((await res.json()).revision)).toBe(1);
});

test('us19 refresh token expired (>900 s) — session ended, then the address is restored', async ({ browser }) => {
	test.skip(!process.env.SENTAI_SLOW, 'set SENTAI_SLOW=1: waits 905 s for the refresh token to expire');
	test.setTimeout(20 * 60_000);
	const first = await browser.newPage();
	const name = `us19-expiry-${Date.now()}`;
	const id = await seedFlow(first.request, oneStepFlow(name));
	await signInAt(first, `?flow=${id}`);
	await expect(flowName(first)).toHaveValue(name);
	const record = await kept(first);
	await first.close(); // no more renewals: the token only ages

	await new Promise((r) => setTimeout(r, 905_000));
	const later = await browser.newPage();
	await dismissGuide(later);
	await later.addInitScript(
		([key, value]) => {
			if (!sessionStorage.getItem('e2e.seeded')) {
				sessionStorage.setItem('e2e.seeded', '1');
				sessionStorage.setItem(key, value);
			}
		},
		[KEPT, JSON.stringify({ ...record, live: false })] as const
	);
	await later.goto(entry(`?flow=${id}`));
	await expect(later.getByText(ENDED)).toBeVisible();
	await submitSignIn(later);
	await expect(flowName(later)).toHaveValue(name);
	await later.close();
});
