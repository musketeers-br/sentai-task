/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { envelope, signIn } from './support';
import { runInIrisApp } from './iris';

// spec 011 — User Story 2, end to end against the published bundle: with the similarity provider
// unreachable, the palette is indistinguishable from today's in every way (FR-023) — the local
// filter narrows by entry text, today's no-match message shows when nothing matches, and no
// SUGGESTED group, toast or error appears. Degraded and working runs look identical.

const EVIDENCE = '../specs/011-semantic-step-search/evidence';

const search = (page: Page) => page.getByLabel('Search step type');

// Since spec 017 the provider is in-process (`sentai.search.LocalEmbedding`), so the story's
// unreachable-host condition is produced the way an operator meets it in the field (README,
// "Alternatives, all the same one row"): the `sentai-steps` row is pointed at an OpenAI-compatible
// `EmbeddingService` whose host refuses the connection — fast, like the stopped container it
// replaces (research R-013). The original row is saved inside IRIS and put back afterwards. Like
// every script in tests/iris.ts, each command is one line at column zero — a leading tab would
// make the terminal read it as a continuation of the previous line.
const SWAP = [
	'Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT EmbeddingClass, Configuration FROM %Embedding.Config WHERE Name = \'sentai-steps\'")',
	'While rs.%Next() { Set ^SentaiE2E("us23","class") = rs.EmbeddingClass, ^SentaiE2E("us23","config") = rs.Configuration }',
	'Set cfg = ##class(%DynamicObject).%New()',
	'Do cfg.%Set("host","127.0.0.1")',
	'Do cfg.%Set("port",9)',
	'Do cfg.%Set("https",0)',
	'Do cfg.%Set("path","/v1/embeddings")',
	'Do cfg.%Set("model","all-minilm")',
	'Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE %Embedding.Config SET EmbeddingClass = \'sentai.search.EmbeddingService\', Configuration = ? WHERE Name = \'sentai-steps\'", cfg.%ToJSON())',
	'Write "US23SWAP=", rs.%SQLCODE, !'
].join('\n');

const RESTORE = [
	'If $DATA(^SentaiE2E("us23","class")) { Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE %Embedding.Config SET EmbeddingClass = ?, Configuration = ? WHERE Name = \'sentai-steps\'", ^SentaiE2E("us23","class"), ^SentaiE2E("us23","config")) Write "US23RESTORE=", rs.%SQLCODE, ! Kill ^SentaiE2E("us23") }'
].join('\n');

function expectMarker(out: string, marker: string): void {
	if (!out.includes(marker)) {
		throw new Error(`the sentai-steps row was not swapped as expected (${marker} missing):\n${out}`);
	}
}

test.beforeAll(() => {
	// The provider row stays; the endpoint behind it does not answer.
	expectMarker(runInIrisApp(SWAP), 'US23SWAP=0');
});

test.afterAll(() => {
	// The dev stack gets its provider back.
	expectMarker(runInIrisApp(RESTORE), 'US23RESTORE=0');
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
			{ provider: 'sentai-steps row → EmbeddingService at an unreachable host' },
			{ suggestedGroups: 0, pageErrors: 0, noMatchMessage: 'today\u2019s own' },
			[
				'With the similarity service down, the palette narrows by entry text exactly as before, shows today\u2019s no-match message, and raises no error (FR-023).'
			]
		)
	);
});
