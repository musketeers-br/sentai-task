/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { runInIrisApp } from './iris';
import { envelope, signIn } from './support';

// spec 011 — User Story 1, end to end against the published bundle: an intent sentence offers a
// SUGGESTED group first (FR-001), a suggested entry is not duplicated in its category group
// (FR-003), and dragging one adds the step exactly as a substring-found entry would (FR-021).
// Needs the real provider row the dev stack carries (quickstart.md §Provider setup) and the
// `ollama` service up.

const EVIDENCE = '../specs/011-semantic-step-search/evidence';

const search = (page: Page) => page.getByLabel('Search step type');
const suggested = (page: Page) => page.locator('[data-suggested="true"]');

test('us22 — an intent sentence offers a SUGGESTED group first; its entry appears once; dragging it adds the step', async ({ page }) => {
	test.slow();
	await signIn(page);
	// Spec 022 FR-012: the drag below targets the canvas, which the gallery now covers until
	// *Start from scratch* starts the blank canvas.
	await page.getByTestId('start-from-scratch').click();
	await expect(page.getByTestId('runbook-gallery')).toHaveCount(0);

	// The intent sentence from the story. The corpus may be building on the first request since
	// the stack came up, so the wait is generous — and throughout it the palette stays today's:
	// the local filter narrows on every keystroke and the list is never blocked (FR-002).
	await search(page).fill('free up disk space');
	await expect(page.getByRole('heading', { name: 'SUGGESTED' })).toBeVisible({ timeout: 30000 });

	// Measured on the shipped corpus with all-minilm (research R-008): the strongest match for
	// this intent is the headroom check, and it is offered first, above the list.
	await expect(suggested(page).first()).toHaveAttribute('data-step-type', 'storage-headroom-check');
	await expect(suggested(page).first()).not.toBeDisabled();

	// FR-003: a suggested entry is removed from its category group, so it is offered once on
	// the screen, never twice.
	await expect(page.locator('[data-step-type="storage-headroom-check"]')).toHaveCount(1);

	// Typing still narrows locally on every keystroke, before and after any request: a substring
	// query keeps today's behaviour, and its entry is likewise offered exactly once.
	await search(page).fill('journal');
	await expect(page.getByRole('heading', { name: 'SUGGESTED' })).toBeVisible({ timeout: 30000 });
	await expect(page.locator('[data-step-type="switch-journal"]')).toHaveCount(1);
	await search(page).fill('free up disk space');
	await expect(suggested(page).first()).toBeVisible({ timeout: 30000 });

	mkdirSync(EVIDENCE, { recursive: true });
	await page.screenshot({ path: `${EVIDENCE}/us22-suggested-intent.png` });

	// Dragging a suggested entry onto the canvas adds the step exactly as a substring-found
	// entry would: one new node, of the suggested type, like every palette add.
	const before = await page.locator('.svelte-flow__node').count();
	await suggested(page).first().dragTo(page.locator('.svelte-flow__pane'), { targetPosition: { x: 320, y: 260 } });
	await expect(page.locator('.svelte-flow__node')).toHaveCount(before + 1);
	await expect(page.locator('.svelte-flow__node').last()).toContainText('Storage headroom check');

	writeFileSync(
		`${EVIDENCE}/us22-semantic-search.json`,
		envelope(
			'us22-semantic-search',
			{ query: 'free up disk space', suggestedFirst: 'storage-headroom-check' },
			{ addedByDrag: 'storage-headroom-check', duplicatesOfSuggested: 0 },
			[
				'The SUGGESTED group renders ahead of today\u2019s list (FR-001), the suggested entry appears once (FR-003), and dragging it adds the step (FR-021).'
			]
		)
	);
});

test('us22 — the corpus the ranking read holds exactly the catalog', async () => {
	// The closed set, structurally, on the real instance. Deliberately only what a published
	// image ships: a fresh `docker compose up -d` has no test classes (the module's test
	// resources load at test time), so this uses src classes only — and runs a search itself,
	// because the corpus is a lazily built cache and an image starts with it empty. The answer
	// is read through a marker because the terminal's own banner and echo precede it.
	const out = runInIrisApp(
		[
			'do ##class(sentai.search.StepSearchService).Search("journal")',
			'set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM sentai_search.StepCorpus")',
			'set rows = -1',
			'if rs.%Next() set rows = rs.%Get("n")',
			'set catalog = ##class(sentai.registry.StepType).GetCatalog().%Size()',
			'write "RESULT:",rows,",",catalog,!'
		].join('\n')
	);
	const found = /RESULT:(\d+),(\d+)/.exec(out);
	expect(found, `the session answered: ${out.slice(-80)}`).not.toBeNull();
	const [rows, catalog] = found!.slice(1).map(Number);
	expect(rows).toBeGreaterThan(0);
	expect(rows).toBe(catalog);
});
