/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import {
	catalogQuery,
	fromWireCatalogPage,
	namespaceOptions,
	NO_FILTERS,
	orderByNextRun,
	type CatalogFilters,
	type WireCatalogPage
} from '../src/lib/catalog/catalog';
import { deleteFlow } from './iris';
import { createPlatformTask, deleteNativeTask, nativeTaskIds, seedFlow, signIn, signInAt, token } from './support';

// spec 007 User Story 3 — Filter and search the catalog (FR-005): every filter is the API's,
// so for each one the rows and "N of M" must equal the API's answer to the same query.

const catalog = (page: Page) => page.getByRole('region', { name: 'Task catalog' });
const EVIDENCE = '../specs/007-canvas-management-screens/evidence';

async function apiPage(page: Page, filters: CatalogFilters): Promise<WireCatalogPage> {
	const res = await page.request.get(`/csp/sentai/api/v1/catalog/tasks${catalogQuery(filters)}`, {
		headers: { Authorization: `Bearer ${await token(page.request)}` }
	});
	expect(res.status()).toBe(200);
	return (await res.json()) as WireCatalogPage;
}

async function expectApiAnswer(page: Page, filters: CatalogFilters) {
	const wire = await apiPage(page, filters);
	const ids = orderByNextRun(fromWireCatalogPage(wire).items).map((t) => String(t.taskId));
	await expect(page.getByTestId('catalog-count')).toHaveText(`${wire.matched} of ${wire.total} tasks`);
	await expect
		.poll(() => catalog(page).getByTestId('catalog-row').evaluateAll((rows) => rows.map((r) => r.getAttribute('data-task-id'))))
		.toEqual(ids);
}

test('us9-catalog-filters — search, namespace, state and destructive-only are answered by the API', async ({ page }) => {
	await signInAt(page, '?view=catalog');
	await expect(catalog(page).getByTestId('catalog-row').first()).toBeVisible();

	// R-2: the namespace options are the unfiltered read's namespaces, plus all.
	const unfiltered = fromWireCatalogPage(await apiPage(page, NO_FILTERS));
	const options = await page.getByLabel('Namespace').locator('option').evaluateAll((o) => o.map((e) => (e as HTMLOptionElement).value));
	expect(options).toEqual(namespaceOptions(unfiltered));
	await expectApiAnswer(page, NO_FILTERS);

	const search = page.getByLabel('Search tasks');
	await search.fill('integrity');
	await expectApiAnswer(page, { ...NO_FILTERS, q: 'integrity' });
	await search.fill('');
	await expectApiAnswer(page, NO_FILTERS);

	await page.getByLabel('Namespace').selectOption('%SYS');
	await expectApiAnswer(page, { ...NO_FILTERS, namespace: '%SYS' });
	await page.getByLabel('Namespace').selectOption('all');

	await page.getByRole('radio', { name: 'Suspended' }).check();
	await expectApiAnswer(page, { ...NO_FILTERS, state: 'suspended' });
	await page.getByRole('radio', { name: 'Scheduled' }).check();
	await expectApiAnswer(page, { ...NO_FILTERS, state: 'scheduled' });
	await page.getByRole('radio', { name: 'All' }).check();

	await page.getByLabel('Destructive only').check();
	await expectApiAnswer(page, { ...NO_FILTERS, destructiveOnly: true });

	// One combination: every filter at once.
	await search.fill('purge');
	await page.getByLabel('Namespace').selectOption('%SYS');
	await page.getByRole('radio', { name: 'Scheduled' }).check();
	await expectApiAnswer(page, { q: 'purge', namespace: '%SYS', state: 'scheduled', destructiveOnly: true });
});

test('us9-catalog-filters SC-003 — with about 150 tasks, first rows < 3 s and a filter update < 2 s', async ({ page }) => {
	test.setTimeout(600_000);
	const request = page.request;
	const total = async () => Number((await apiPage(page, NO_FILTERS)).total);
	const before = await total();

	// Seed: 3 x 45 platform tasks named as the legacy per-step form of 3 flows (spec 015 schedules
	// one task per flow, so the load is created through the management API directly).
	const flowIds: string[] = [];
	try {
		for (let f = 0; f < 3; f++) {
			const id = await seedFlow(request, { name: `SC-003 load ${Date.now()}-${f}`, defaultCategory: 'Default', steps: [{ id: '01', type: 'integrity-check', taskName: 'SC-003', namespace: 'USER', runAsUser: 'irisadm', wqmCategory: 'Default', databaseDirectory: '/usr/irissys/mgr/user/', timeoutMinutes: 30 }], edges: [], joins: [], canvasGeometry: { nodes: {} } });
			flowIds.push(id);
			for (let i = 1; i <= 45; i++) await createPlatformTask(request, `SentaiTask: ${id}#${String(i).padStart(2, '0')}`, id, String(i).padStart(2, '0'));
		}
		const seeded = await total();
		expect(seeded).toBeGreaterThanOrEqual(before + 135);

		await signIn(page);
		const runs: Array<{ firstRowsMs: number; filterMs: number }> = [];
		for (let run = 0; run < 3; run++) {
			let start = Date.now();
			await page.getByRole('button', { name: 'Task catalog', exact: true }).click();
			await expect(page.getByTestId('catalog-count')).toHaveText(`${seeded} of ${seeded} tasks`, { timeout: 10_000 });
			await expect(catalog(page).getByTestId('catalog-row').first()).toBeVisible();
			const firstRowsMs = Date.now() - start;

			// The typed text waits out its 300 ms debounce inside this measure.
			start = Date.now();
			await page.getByLabel('Search tasks').fill(`SentaiTask: ${flowIds[run]}#`);
			await expect(page.getByTestId('catalog-count')).toHaveText(`45 of ${seeded} tasks`, { timeout: 10_000 });
			const filterMs = Date.now() - start;
			runs.push({ firstRowsMs, filterMs });

			await page.getByLabel('Search tasks').fill('');
			await page.getByRole('button', { name: 'Flows', exact: true }).click();
		}

		mkdirSync(EVIDENCE, { recursive: true });
		writeFileSync(
			`${EVIDENCE}/sc003-timing.txt`,
			[
				`SC-003 timing — ${new Date().toISOString()}`,
				`Tasks on the instance: ${seeded} (${before} before seeding; 3 x 45 tasks created through the management API).`,
				'Measured in the browser at 1440x900 against the dev container, from the click/keystroke to the rendered answer.',
				...runs.map((r, i) => `run ${i + 1}: first rows ${r.firstRowsMs} ms (limit 3000) · filter update ${r.filterMs} ms incl. 300 ms debounce (limit 2000)`),
				'Seeded tasks and flows were deleted afterwards; the task count returned to its value before the run.'
			].join('\n') + '\n'
		);
		for (const r of runs) {
			expect(r.firstRowsMs).toBeLessThan(3000);
			expect(r.filterMs).toBeLessThan(2000);
		}
	} finally {
		for (const id of flowIds) {
			for (const taskId of await nativeTaskIds(request, id)) await deleteNativeTask(request, taskId);
			deleteFlow(id);
		}
	}
	expect(await total()).toBe(before);
});
