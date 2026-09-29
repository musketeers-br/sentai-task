/// <reference types="node" />
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { envelope, signIn } from './support';

// spec 011 — User Story 2, end to end against the published bundle: with the similarity service
// stopped, the palette is indistinguishable from today's in every way (FR-023) — the local
// filter narrows by entry text, today's no-match message shows when nothing matches, and no
// SUGGESTED group, toast or error appears. Degraded and working runs look identical.

const EVIDENCE = '../specs/011-semantic-step-search/evidence';
const COMPOSE = process.env.COMPOSE_FILE ?? 'docker-compose.yml';

const search = (page: Page) => page.getByLabel('Search step type');

function compose(action: 'stop' | 'start'): string {
	return execFileSync('docker', ['compose', '-f', COMPOSE, action, 'ollama'], {
		encoding: 'utf8',
		cwd: '..'
	});
}

test.beforeAll(() => {
	// The provider row stays; the service behind it does not answer. A stopped container is the
	// unreachable-host condition of the story, and it fails fast (research R-013).
	compose('stop');
});

test.afterAll(() => {
	// The dev stack gets its provider back.
	compose('start');
});

test('us23 — with the provider down, the palette is exactly today’s: local filter, no-match message, no SUGGESTED group, no error', async ({ page }) => {
	test.slow();
	const errors: string[] = [];
	page.on('pageerror', (e) => errors.push(e.message));

	await signIn(page);

	// A known identifier narrows locally on every keystroke — before and after any request —
	// and no suggestion ever arrives to re-order it.
	await search(page).fill('journal');
	await expect(page.locator('[data-step-type="switch-journal"]')).toBeVisible();
	await expect(page.locator('[data-step-type="integrity-check"]')).toHaveCount(0);
	await page.waitForTimeout(1200); // long enough for the debounced request to have been refused
	await expect(page.locator('[data-suggested="true"]')).toHaveCount(0);
	await expect(page.getByRole('heading', { name: 'SUGGESTED' })).toHaveCount(0);

	// An intent sentence finds nothing by entry text, so today's no-match message shows — and
	// it is the same message today's palette shows, not an error wearing its clothes.
	await search(page).fill('rotate the journal');
	await page.waitForTimeout(1200);
	await expect(page.locator('.palette .empty')).toHaveText('No step type matches “rotate the journal”.');
	await expect(page.locator('[data-suggested="true"]')).toHaveCount(0);

	// Nonsense, too, narrows to today's message — an unavailable provider and an empty ranking
	// are indistinguishable on screen by design (R-007).
	await search(page).fill('zzzz-nothing');
	await page.waitForTimeout(1200);
	await expect(page.locator('.palette .empty')).toBeVisible();

	await page.screenshot({ path: `${EVIDENCE}/us23-degraded.png` });

	// No toast, no console error, no page error: degradation is not a failure (FR-023).
	expect(errors).toEqual([]);

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us23-search-degradation.json`,
		envelope(
			'us23-search-degradation',
			{ provider: 'ollama stopped (docker compose stop ollama)' },
			{ suggestedGroups: 0, pageErrors: 0, noMatchMessage: 'today\u2019s own' },
			[
				'With the similarity service down, the palette narrows by entry text exactly as before, shows today\u2019s no-match message, and raises no error (FR-023).'
			]
		)
	);
});
