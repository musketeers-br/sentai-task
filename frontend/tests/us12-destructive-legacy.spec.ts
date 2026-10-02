import { expect, test } from '@playwright/test';
import { hexToRgb, paletteEntry, seedFlow, signIn } from './support';

// spec 007 User Story 6 (T010): a declared destructive type carries the three destructive signals
// (the typed confirmation is us14); a legacy `custom` step is read-only and not supported.

test('us12 — purge-task-history from Custom is destructive on the canvas; legacy custom is read-only', async ({ page }) => {
	const id = await seedFlow(page.request, {
		name: `us12 legacy ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [{ id: '01', type: 'custom', taskName: 'Old custom step', namespace: 'USER', runAsUser: 'irisadm', wqmCategory: 'Default', customClass: 'Some.Old.Task' }],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	});
	await signIn(page, `?flow=${id}`);

	// Legacy custom: not supported, class shown but not editable.
	const legacy = page.locator('.svelte-flow__node[data-id="01"]');
	await legacy.locator('h3').click();
	const inspector = page.getByLabel('Inspector', { exact: true });
	await expect(inspector.getByTestId('custom-class-readonly')).toHaveText('Some.Old.Task');
	await expect(inspector).toContainText('not supported');
	await expect(inspector.getByLabel('Custom class')).toHaveCount(0);

	// A declared destructive type dropped from the Custom group.
	const pane = page.locator('.svelte-flow__pane');
	await (await paletteEntry(page, 'purge-task-history')).dragTo(pane, { targetPosition: { x: 420, y: 120 } });
	const purge = page.locator('.svelte-flow__node').filter({ hasText: 'Purge task history' });
	await expect(purge.getByTestId('hazard-band')).toBeVisible();
	await expect(purge.getByTestId('destructive-seal')).toHaveText('DESTRUCTIVE');
	await expect(purge.locator('article')).toHaveCSS(
		'border-left-color',
		hexToRgb(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--category-purge')))
	);
	await purge.locator('h3').click();
	await expect(inspector.getByRole('heading', { name: /DESTRUCTIVE STEP/ })).toBeVisible();

	// Zoomed out, the signals stay.
	await page.getByRole('button', { name: /zoom out/i }).click();
	await page.getByRole('button', { name: /zoom out/i }).click();
	await expect(purge.getByTestId('destructive-seal')).toBeVisible();
});
