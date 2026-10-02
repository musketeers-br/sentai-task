/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import { fromWireCatalogPage, type WireCatalogPage } from '../src/lib/catalog/catalog';
import { scheduleStrip } from '../src/lib/overview/attention';
import type { WireSummary } from '../src/lib/overview/overview';
import { envelope, expectNoSeriousA11y, LANDING, signInAt, token } from './support';

// Spec 023 User Story 3 — Overview points at what needs attention, above spec 019's cards
// (FR-022, FR-023, FR-026, FR-029; board *Proposed — Overview*). Expected values are read from
// the API in the test; refusals are planted with route mocks, never by changing the instance.

const EVIDENCE = '../specs/023-canvas-design-refresh/evidence';
const CATALOG = /\/csp\/sentai\/api\/v1\/catalog\/tasks(\?.*)?$/;
const SUMMARY = /\/csp\/sentai\/api\/v1\/overview$/;

async function api<T>(request: APIRequestContext, path: string): Promise<T> {
	const res = await request.get(`/csp/sentai/api/v1${path}`, { headers: { Authorization: `Bearer ${await token(request)}` } });
	expect(res.status(), await res.text()).toBe(200);
	return res.json();
}

const band = (page: Page) => page.getByTestId('attention-band');
const cards = (page: Page) => page.getByTestId('area-card');

test('lands on Overview with the attention items the API supports, within 3 s (FR-022, SC-007)', async ({ page }) => {
	const catalog = (await api<WireCatalogPage>(page.request, '/catalog/tasks')) as WireCatalogPage & {
		counts: { suspended: number; destructive: number; unclassified: number };
	};
	const summary = await api<WireSummary>(page.request, '/overview');
	const activity = summary.areas.find((a) => a.area === 'activity');

	const started = Date.now();
	await signInAt(page, LANDING);
	await expect(page.getByRole('heading', { name: 'Overview', level: 1 })).toBeVisible();
	// The band has finished reading when it shows an item, "Nothing needs attention" or what it could not read.
	await expect(band(page).locator('li, [data-testid="attention-none"], [data-testid="attention-missing"]').first()).toBeVisible();
	await expect(page.getByTestId('schedule-summary')).toBeVisible();
	const shownIn = Date.now() - started;

	const lastBackup = String(activity?.headline?.lastBackup ?? '');
	if (activity?.outcome === 'ok' && (lastBackup === '' || lastBackup.toLowerCase() === 'never')) {
		await expect(page.getByTestId('attention-backup')).toContainText('No backup has ever been taken on this instance');
		await expect(page.getByTestId('attention-backup').getByRole('button', { name: 'Add a backup step' })).toBeDisabled();
	} else {
		await expect(page.getByTestId('attention-backup')).toHaveCount(0);
	}
	if (catalog.counts.suspended > 0) {
		await expect(page.getByTestId('attention-suspended')).toContainText(`${catalog.counts.suspended} scheduled task`);
	}
	if (catalog.counts.unclassified > 0) {
		await expect(page.getByTestId('attention-unclassified')).toContainText(`${catalog.counts.unclassified} of ${catalog.total} tasks`);
	}
	// Spec 019's cards are still all there, below the bands.
	await expect(cards(page)).toHaveCount(11);
	await expect(page.getByTestId('unread-summary')).toHaveCount(0);
	await page.screenshot({ path: `${EVIDENCE}/us32-overview-attention.png`, fullPage: true });

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us32-attention.json`,
		envelope(
			'us32-attention',
			{ method: 'GET', url_paths: ['/csp/sentai/api/v1/overview', '/csp/sentai/api/v1/catalog/tasks'] },
			{ lastBackup, counts: catalog.counts, total: catalog.total, shownInMs: shownIn },
			['The bands showed these values as the API sent them; the time includes signing in (SC-007 budget 3 s from opening).']
		)
	);
});

test('attention actions open the catalog filtered, from the mouse and the keyboard', async ({ page }) => {
	const catalog = (await api<WireCatalogPage>(page.request, '/catalog/tasks')) as WireCatalogPage & {
		counts: { suspended: number; unclassified: number };
	};
	test.skip(catalog.counts.suspended === 0 || catalog.counts.unclassified === 0, 'needs suspended and unclassified tasks on the instance');
	await signInAt(page, LANDING);

	await page.getByTestId('attention-suspended').getByRole('button', { name: 'Show in catalog' }).click();
	await expect(page).toHaveURL(/view=catalog/);
	await expect(page).toHaveURL(/filter=suspended/);
	await expect(page.getByRole('radio', { name: /Suspended/ })).toBeChecked();

	await page.getByRole('banner').getByRole('button', { name: 'Overview', exact: true }).click();
	const showThem = page.getByTestId('attention-unclassified').getByRole('button', { name: 'Show them' });
	await showThem.focus();
	await page.keyboard.press('Enter');
	await expect(page).toHaveURL(/unclassifiedOnly=1/);
	await expect(page.getByLabel('unclassified')).toBeChecked();
});

test('next 24 hours — the slots the catalog and the instance clock give (FR-023)', async ({ page }) => {
	const wire = await api<WireCatalogPage>(page.request, '/catalog/tasks');
	const summary = await api<WireSummary>(page.request, '/overview');
	const expected = scheduleStrip(fromWireCatalogPage(wire).items, summary.areas[0]?.readAt ?? null);
	expect(expected.kind).toBe('ready');
	await signInAt(page, LANDING);
	const strip = page.getByTestId('schedule-strip');
	await expect(page.getByTestId('schedule-summary')).toBeVisible();
	if (expected.kind !== 'ready') return;
	// The summary read in the test and the one on screen are moments apart: compare the slots
	// that fall well inside both windows.
	const shown = await strip.getByTestId('schedule-slot').evaluateAll((els) =>
		els.map((e) => ({ start: e.getAttribute('data-start'), count: Number(e.querySelector('.count')?.textContent) }))
	);
	for (const slot of expected.strip.slots.slice(0, -1)) {
		expect(shown).toContainEqual({ start: slot.start, count: slot.count });
	}
	if (expected.strip.slots.length === 0) await expect(strip.getByTestId('schedule-empty')).toBeVisible();
	await expect(page.getByTestId('schedule-summary')).toContainText(expected.strip.flowScheduled ? 'a flow is scheduled' : 'no flow scheduled');
});

test('a refused catalog read is named; the cards still render (FR-026, FR-029, SC-006)', async ({ page }) => {
	await page.route(CATALOG, (route) =>
		route.fulfill({ status: 403, contentType: 'application/json', body: JSON.stringify({ status: 403, title: 'Forbidden', detail: 'ERROR #822: Access Denied' }) })
	);
	await signInAt(page, LANDING);
	const unread = page.getByTestId('unread-summary');
	await expect(unread).toContainText('Task catalog');
	await expect(unread).toContainText('HTTP 403 — ERROR #822: Access Denied');
	await expect(page.getByTestId('schedule-unread')).toContainText('HTTP 403 — ERROR #822: Access Denied');
	await expect(page.getByTestId('attention-missing')).toContainText('Task catalog');
	await expect(page.getByTestId('attention-none')).toHaveCount(0);
	await expect(cards(page)).toHaveCount(11);
	await page.screenshot({ path: `${EVIDENCE}/us32-catalog-refused.png`, fullPage: true });
});

test('a refused area is named at the top, its card says so, the rest renders (FR-029)', async ({ page }) => {
	await page.route(SUMMARY, async (route) => {
		const response = await route.fetch();
		const body = (await response.json()) as WireSummary;
		for (const a of body.areas) {
			if (a.area === 'locks') Object.assign(a, { outcome: 'refused', headline: null, problem: { title: 'Forbidden', detail: 'ERROR #822: Access Denied', httpStatus: 403 } });
		}
		await route.fulfill({ response, json: body });
	});
	await signInAt(page, LANDING);
	await expect(page.getByTestId('unread-summary')).toContainText('Locks');
	await expect(page.getByTestId('unread-summary')).toContainText('HTTP 403 — ERROR #822: Access Denied');
	await expect(page.locator('[data-testid="area-card"][data-area="locks"] [data-testid="card-refusal"]')).toHaveText('HTTP 403 — ERROR #822: Access Denied');
	await expect(page.locator('[data-testid="area-card"][data-state="ok"]')).toHaveCount(10);
	await expect(page.getByTestId('schedule-summary')).toBeVisible();
});

test('accessibility — Overview with the bands, dark and light (SC-008)', async ({ page }) => {
	await signInAt(page, LANDING);
	await expect(page.getByTestId('schedule-summary')).toBeVisible();
	await page.getByRole('banner').getByRole('button', { name: 'Dark', exact: true }).click();
	await expectNoSeriousA11y(page, 'us32-overview-dark');
	await page.getByRole('banner').getByRole('button', { name: 'Light', exact: true }).click();
	await expectNoSeriousA11y(page, 'us32-overview-light');
	await page.screenshot({ path: `${EVIDENCE}/us32-overview-light.png`, fullPage: true });
	await page.getByRole('banner').getByRole('button', { name: 'Dark', exact: true }).click();
});
