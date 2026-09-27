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
import { signInAt, token } from './support';

// spec 007 User Story 3 — Filter and search the catalog (FR-005): every filter is the API's,
// so for each one the rows and "N of M" must equal the API's answer to the same query.

const catalog = (page: Page) => page.getByRole('region', { name: 'Task catalog' });

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
