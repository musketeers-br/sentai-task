import { expect, test, type Page } from '@playwright/test';
import { seedFlow, signIn, signInAt, submitSignIn, v1Flow } from './support';

// spec 007 User Story 1 — See the platform's scheduled tasks (FR-001, FR-002).

const catalog = (page: Page) => page.getByRole('region', { name: 'Task catalog' });

test('us7-catalog navigation — reachable from the top bar, addressable, back keeps the open flow', async ({ page }) => {
	const id = await seedFlow(page.request, v1Flow(`us7 navigation ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	const flowsTab = page.getByRole('button', { name: 'Flows', exact: true });
	const catalogTab = page.getByRole('button', { name: 'Task catalog', exact: true });
	await expect(flowsTab).toHaveAttribute('aria-current', 'page');

	// An unsaved edit that must survive the trip to the catalog and back.
	const edited = `us7 unsaved edit ${Date.now()}`;
	await page.getByLabel('Flow name').fill(edited);
	await expect(page.getByTestId('flow-meta')).toContainText('edited');

	await catalogTab.click();
	await expect(page).toHaveURL(/[?&]view=catalog/);
	await expect(catalog(page)).toBeVisible();
	await expect(catalogTab).toHaveAttribute('aria-current', 'page');
	// Flow actions belong to the Flows screen only.
	await expect(page.getByRole('button', { name: 'Run now' })).toHaveCount(0);
	await expect(page.getByLabel('Flow name')).toHaveCount(0);
	// The list comes from the API: a task every instance has.
	await expect(catalog(page).getByText('Integrity Check', { exact: true })).toBeVisible();

	await page.goBack();
	await expect(page).not.toHaveURL(/view=catalog/);
	await expect(page).toHaveURL(new RegExp(`[?&]flow=${id}`));
	await expect(page.getByLabel('Flow name')).toHaveValue(edited);
	await expect(page.getByTestId('flow-meta')).toContainText('edited');

	await page.goForward();
	await expect(catalog(page)).toBeVisible();

	// Flows tab returns to the editor, still with the edit.
	await flowsTab.click();
	await expect(page.getByLabel('Flow name')).toHaveValue(edited);

	// A deep link opens the catalog right after sign-in, and a reload keeps it there
	// (tokens are in memory only, so the reload asks for the sign-in again).
	const fresh = await page.context().newPage();
	await signInAt(fresh, '?view=catalog');
	await expect(catalog(fresh)).toBeVisible();
	await fresh.reload();
	await submitSignIn(fresh);
	await expect(catalog(fresh)).toBeVisible();
	await expect(fresh).toHaveURL(/[?&]view=catalog/);
	await fresh.close();
});
