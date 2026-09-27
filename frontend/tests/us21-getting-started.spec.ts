/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { EXAMPLE_FLOW_NAME } from './iris';
import { envelope, signInAt, submitSignIn } from './support';
import { contrastFailures } from './theming';

// spec 010 User Story 5 — Getting-started guide (FR-020…FR-025, SC-006).

const EVIDENCE = '../specs/010-canvas-onboarding-usability/evidence';
const TITLES = ['Welcome', 'Open the example', 'Build a flow', 'Validate and run', 'Save, Save as, Open', 'Schedule and explore'];

const guide = (page: Page) => page.getByRole('dialog', { name: 'Getting started' });
const dontShow = (page: Page) => guide(page).getByLabel("Don't show this again");

async function freshSignIn(page: Page, query = '') {
	await signInAt(page, query, undefined, undefined, { guide: 'fresh' });
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
}

async function signOutAndIn(page: Page) {
	await page.getByRole('button', { name: 'Sign out' }).click();
	await submitSignIn(page);
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
}

async function openFromHelp(page: Page) {
	await page.getByRole('banner').getByRole('button', { name: 'Help' }).click();
	await page.getByRole('menuitem', { name: 'Getting started' }).click();
	await expect(guide(page)).toBeVisible();
}

/** The guide is not shown: waited long enough for an automatic opening to have happened. */
async function expectNoAutoOpen(page: Page) {
	await page.waitForTimeout(800);
	await expect(guide(page)).toHaveCount(0);
}

test('us21 steps — after sign-in the guide shows the six steps in order, one at a time (FR-020, FR-021)', async ({ page }) => {
	await freshSignIn(page);
	await expect(guide(page)).toBeVisible();
	await expect(guide(page).getByText('Step 1 of 6')).toBeVisible();
	await expect(guide(page).getByRole('button', { name: 'Back' })).toBeDisabled();
	await expect(dontShow(page)).not.toBeChecked();
	await page.screenshot({ path: `${EVIDENCE}/us21-guide-step1-dark.png` });

	const seen: string[] = [];
	for (let i = 0; i < 6; i++) {
		await expect(guide(page).getByText(`Step ${i + 1} of 6`)).toBeVisible();
		seen.push(await guide(page).getByTestId('guide-step-title').innerText());
		await expect(guide(page).getByRole('button', { name: 'Close' })).toBeVisible();
		if (i < 5) await guide(page).getByRole('button', { name: 'Next' }).click();
	}
	expect(seen).toEqual(TITLES);
	await expect(guide(page).getByRole('button', { name: 'Next' })).toHaveCount(0);
	await guide(page).getByRole('button', { name: 'Back' }).click();
	await expect(guide(page).getByText('Step 5 of 6')).toBeVisible();
	await guide(page).getByRole('button', { name: 'Next' }).click();
	await guide(page).getByRole('button', { name: 'Get started' }).click();
	await expect(guide(page)).toHaveCount(0);

	await page.getByRole('button', { name: 'Light', exact: true }).click();
	await openFromHelp(page);
	await page.screenshot({ path: `${EVIDENCE}/us21-guide-step1-light.png` });
	await page.keyboard.press('Escape');
	await page.getByRole('button', { name: 'Dark', exact: true }).click();

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(`${EVIDENCE}/us21-guide.json`, envelope('us21-guide', { ui: 'Getting started' }, { steps: seen }, ['Titles in the order Story 5 lists them.']));
});

test('us21 keyboard — a modal dialog with its title; focus stays inside; Escape closes; focus returns (FR-025)', async ({ page }) => {
	await freshSignIn(page);
	await page.keyboard.press('Escape');
	await expect(guide(page)).toHaveCount(0);

	// From Help: focus must come back to the Help button.
	await openFromHelp(page);
	const dialog = page.locator('dialog[open]');
	await expect(dialog).toHaveAttribute('aria-modal', 'true');
	await expect(guide(page)).toHaveAccessibleName('Getting started');
	expect(await page.evaluate(() => document.activeElement?.closest('dialog') !== null)).toBe(true);
	for (let i = 0; i < 15; i++) {
		await page.keyboard.press('Tab');
		expect(await page.evaluate(() => document.activeElement?.closest('dialog[open]') !== null), `Tab #${i + 1}`).toBe(true);
	}
	await page.keyboard.press('Escape');
	await expect(guide(page)).toHaveCount(0);
	await expect(page.getByRole('banner').getByRole('button', { name: 'Help' })).toBeFocused();
});

test('us21 visit — closed without ticking: not again in this visit or on reload, again on the next sign-in (scenario 5.5)', async ({ page }) => {
	await freshSignIn(page);
	await expect(guide(page)).toBeVisible();
	await guide(page).getByRole('button', { name: 'Close' }).click();
	await page.reload(); // same visit: the sign-in was kept, not typed
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	await expectNoAutoOpen(page);
	await signOutAndIn(page);
	await expect(guide(page)).toBeVisible();
});

test('us21 SC-006 — ticked: 0 automatic openings over 5 sign-ins; Help opens it every time; unticking restores it', async ({ page }) => {
	test.slow();
	await freshSignIn(page);
	await dontShow(page).check();
	await guide(page).getByRole('button', { name: 'Close' }).click();

	for (let i = 0; i < 5; i++) {
		await signOutAndIn(page);
		await expectNoAutoOpen(page);
		await openFromHelp(page);
		await expect(guide(page).getByText('Step 1 of 6')).toBeVisible();
		await expect(dontShow(page)).toBeChecked();
		await guide(page).getByRole('button', { name: 'Close' }).click();
	}

	// Scenario 5.6: untick from Help, close — automatic again.
	await openFromHelp(page);
	await dontShow(page).uncheck();
	await guide(page).getByRole('button', { name: 'Close' }).click();
	await signOutAndIn(page);
	await expect(guide(page)).toBeVisible();
});

test('us21 storage blocked — the guide still opens and closes, with no error, and comes back next sign-in (FR-024)', async ({ page }) => {
	const errors: string[] = [];
	page.on('pageerror', (e) => errors.push(e.message));
	page.on('console', (m) => {
		if (m.type() === 'error') errors.push(m.text());
	});
	// Only localStorage refuses (a site-data block); the tab's sessionStorage still works.
	await page.addInitScript(() => {
		const local = window.localStorage;
		const refuse = () => {
			throw new DOMException('The operation is insecure.', 'SecurityError');
		};
		for (const m of ['getItem', 'setItem', 'removeItem'] as const) Object.defineProperty(local, m, { value: refuse });
	});
	await freshSignIn(page);
	await expect(guide(page)).toBeVisible();
	await dontShow(page).check();
	await guide(page).getByRole('button', { name: 'Close' }).click();
	await expect(guide(page)).toHaveCount(0);
	await signOutAndIn(page);
	await expect(guide(page)).toBeVisible(); // the choice could not be kept
	expect(errors).toEqual([]);
});

test('us21 example step — opens the example; hidden when the example is not available (FR-016c, FR-019)', async ({ page }) => {
	await freshSignIn(page);
	await guide(page).getByRole('button', { name: 'Next' }).click();
	await expect(guide(page).getByTestId('guide-step-title')).toHaveText('Open the example');
	await guide(page).getByRole('button', { name: 'Open example flow' }).click();
	await expect(guide(page)).toHaveCount(0);
	await expect(page.getByLabel('Flow name')).toHaveValue(EXAMPLE_FLOW_NAME);

	await page.route('**/csp/sentai/api/v1/catalog/step-types', async (route) => {
		const types = (await (await route.fetch()).json()) as Array<Record<string, unknown>>;
		return route.fulfill({ status: 200, json: types.map((t) => (t.type === 'db-size-report' ? { ...t, available: false } : t)) });
	});
	await page.reload();
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	await openFromHelp(page);
	await guide(page).getByRole('button', { name: 'Next' }).click();
	await expect(guide(page).getByTestId('guide-step-title')).toHaveText('Open the example');
	await expect(guide(page).getByTestId('guide-step-body')).not.toBeEmpty();
	await expect(guide(page).getByRole('button', { name: 'Open example flow' })).toHaveCount(0);
});

test('us21 on first use — the guide is above the empty-canvas invitation, which stays once it closes (edge case)', async ({ page }) => {
	await page.route('**/csp/sentai/api/v1/flows', (route) =>
		route.request().method() === 'GET' ? route.fulfill({ status: 200, json: [] }) : route.continue()
	);
	await freshSignIn(page);
	await expect(guide(page)).toBeVisible();
	expect(await page.evaluate(() => document.querySelector('dialog[open]')?.matches(':modal'))).toBe(true);
	await expect(page.getByTestId('example-invitation')).toBeAttached();
	await guide(page).getByRole('button', { name: 'Close' }).click();
	await expect(page.getByTestId('example-invitation')).toBeVisible();
});

test('us21 top bar — with Help, every control still fits at 1440 px', async ({ page }) => {
	await signInAt(page);
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
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
	for (const screen of ['Task catalog', 'Targets']) {
		await page.getByRole('button', { name: screen }).click();
		await expect(page.getByRole('banner').getByRole('button', { name: 'Help' })).toBeVisible();
	}
});

test('us21 theming — the new dialogs and the invitation read in both themes (T054)', async ({ page }) => {
	await page.route('**/csp/sentai/api/v1/flows', (route) =>
		route.request().method() === 'GET' ? route.fulfill({ status: 200, json: [] }) : route.continue()
	);
	await signInAt(page);
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	const failures: Record<string, unknown> = {};
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		const shot = async (what: string) => {
			await page.mouse.move(0, 0);
			const found = await contrastFailures(page);
			if (found.length > 0) failures[`${theme}/${what}`] = found;
			await page.screenshot({ path: `${EVIDENCE}/theming-${what}-${theme.toLowerCase()}.png` });
		};
		await expect(page.getByTestId('example-invitation')).toBeVisible();
		await shot('invitation');

		await page.getByRole('banner').getByRole('button', { name: 'Open flow…' }).click();
		await expect(page.getByRole('dialog', { name: 'Open flow' })).toBeVisible();
		await shot('open-flow');
		await page.keyboard.press('Escape');

		await openFromHelp(page);
		await shot('guide');
		await page.keyboard.press('Escape');

		await page.locator('[data-step-type="db-size-report"]').click();
		await page.getByRole('banner').getByRole('button', { name: 'More' }).click();
		await page.getByRole('menuitem', { name: 'Save as…' }).click();
		await expect(page.getByRole('dialog', { name: 'Save as a new flow' })).toBeVisible();
		await shot('save-as');
		await page.keyboard.press('Escape');

		await page.getByRole('banner').getByRole('button', { name: 'More' }).click();
		await page.getByRole('menuitem', { name: 'New flow' }).click();
		await expect(page.getByRole('dialog', { name: /^Save changes to / })).toBeVisible();
		await shot('unsaved-changes');
		await page.getByRole('dialog', { name: /^Save changes to / }).getByRole('button', { name: 'Discard' }).click();
		await expect(page.locator('.svelte-flow__node')).toHaveCount(0);
	}
	expect(failures, 'every text ≥ 4.5:1 (≥ 3:1 at ≥ 24 px)').toEqual({});
});
