import { expect, test, type Page } from '@playwright/test';
import { connect, expectNoSeriousA11y, paletteEntry, signIn } from './support';

// Spec 023 User Story 1 — the flow editor says what the flow is and what to do next
// (FR-001, FR-004–FR-013; board *Proposed — flow chrome*).

const EVIDENCE = '../specs/023-canvas-design-refresh/evidence';

const topBar = (page: Page) => page.locator('header.top-bar');
const flowBar = (page: Page) => page.getByRole('toolbar', { name: 'Flow' });

async function setTheme(page: Page, theme: 'Dark' | 'Light') {
	await topBar(page).getByRole('button', { name: theme, exact: true }).click();
}

test('global bar — the same items on every screen, and no flow control in it (FR-001)', async ({ page }) => {
	await signIn(page);
	const expected = ['Overview', 'Flows', 'Task catalog', 'Targets', 'Runs', 'Dark', 'Light', 'Sign out'];
	for (const tab of ['Overview', 'Task catalog', 'Targets', 'Runs', 'Flows']) {
		await topBar(page).getByRole('button', { name: tab, exact: true }).click();
		await expect(topBar(page).getByRole('button', { name: tab, exact: true })).toHaveAttribute('aria-current', 'page');
		for (const name of expected) await expect(topBar(page).getByRole('button', { name, exact: true })).toBeVisible();
		await expect(topBar(page).getByRole('button', { name: /^Help/ })).toBeVisible();
		for (const name of ['Save', 'Save flow', 'Validate', 'Run now', 'Schedule', 'Open…']) {
			await expect(topBar(page).getByRole('button', { name, exact: true })).toHaveCount(0);
		}
	}
	// The flow bar exists on Flows only.
	await expect(flowBar(page)).toBeVisible();
	await topBar(page).getByRole('button', { name: 'Runs', exact: true }).click();
	await expect(flowBar(page)).toHaveCount(0);
});

test('flow bar — save state, actions and the visible reason they are disabled (FR-005, FR-006)', async ({ page }) => {
	await signIn(page);
	const bar = flowBar(page);
	await expect(bar.getByLabel('Flow name')).toBeVisible();
	await expect(bar.getByTestId('flow-meta')).toHaveText('unsaved');
	for (const name of ['Open…', 'Save', 'Validate', 'Run now', 'Schedule']) {
		await expect(bar.getByRole('button', { name, exact: true })).toBeVisible();
	}
	for (const name of ['Validate', 'Run now', 'Schedule']) {
		await expect(bar.getByRole('button', { name, exact: true })).toBeDisabled();
	}
	// Said as text, without hovering.
	await expect(bar.getByTestId('flow-actions-reason')).toHaveText('add a step to enable running');

	// ⋯ holds New flow, Save as… and Run history — and opens from the keyboard (FR-004).
	const more = bar.getByRole('button', { name: 'More flow actions' });
	await more.focus();
	await page.keyboard.press('Enter');
	const menu = page.getByRole('menu');
	for (const name of ['New flow', 'Save as…', 'Run history']) await expect(menu.getByRole('menuitem', { name })).toBeVisible();
	await page.keyboard.press('Escape');
	await expect(menu).toHaveCount(0);
	await expect(more).toBeFocused();

	// One step: the reason goes away and the actions open up.
	await (await paletteEntry(page, 'integrity-check')).click();
	await expect(bar.getByTestId('flow-actions-reason')).toHaveCount(0);
	await expect(bar.getByRole('button', { name: 'Validate', exact: true })).toBeEnabled();
	await expect(bar.getByRole('button', { name: 'Run now', exact: true })).toBeEnabled();

	// A failed validation blocks Run now and Schedule and says where to look (US1 scenario 4).
	// The same planted error as us2 Q4: a namespace the dev image does not have.
	await page.locator('.svelte-flow__node[data-id="01"]').click();
	await page.locator('#insp-namespace').fill('DOCBOOK');
	await bar.getByRole('button', { name: 'Validate', exact: true }).click();
	await expect(page.getByTestId('status-errors')).toBeVisible();
	await expect(bar.getByTestId('flow-actions-reason')).toHaveText('fix the validation errors in the status bar');
	await expect(bar.getByRole('button', { name: 'Run now', exact: true })).toBeDisabled();
	await expect(bar.getByRole('button', { name: 'Schedule', exact: true })).toBeDisabled();
});

test('empty canvas, inspector and status bar say how to start (FR-007–FR-012)', async ({ page }) => {
	await signIn(page);
	const empty = page.getByTestId('empty-canvas');
	await expect(empty.getByRole('heading', { name: 'This flow is empty' })).toBeVisible();
	await expect(empty).toContainText('Drag a step type from the left onto the canvas');
	await expect(empty).toContainText('make a join');
	// The canvas's own legend tells a sequence from a join (spec 002), beside the card.
	await expect(page.locator('.canvas-area')).toContainText('sequence');
	await expect(page.locator('.canvas-area')).toContainText('join (fan-in)');
	await expect(empty.getByRole('button', { name: 'Start from a template' })).toBeVisible();
	await expect(empty.getByRole('button', { name: 'Import from the task catalog' })).toBeVisible();

	// Nothing selected: the flow's own properties.
	const flowSection = page.getByTestId('inspector-flow');
	await expect(flowSection).toContainText(await page.getByLabel('Flow name').inputValue());
	await expect(flowSection.getByLabel('WQM category')).toHaveValue(/.+/);
	await expect(page.getByTestId('inspector-nothing-selected')).toHaveText(
		'Nothing selected. Click a step on the canvas and its parameters appear here.'
	);

	// Zoom controls stay on the canvas (FR-012); the status bar gives snap and zoom.
	await expect(page.locator('.svelte-flow__controls-zoomin')).toBeVisible();
	await expect(page.locator('.svelte-flow__controls-zoomout')).toBeVisible();
	await expect(page.locator('.svelte-flow__controls-fitview')).toBeVisible();
	await expect(page.locator('footer.status-bar')).toContainText('snap 8 px');
	await expect(page.getByTestId('zoom')).toHaveText(/^zoom \d+%$/);
	await page.screenshot({ path: `${EVIDENCE}/us30-empty-canvas-dark.png` });

	// Dragging through the card still lands on the canvas: the card lets pointer events through.
	const pane = page.locator('.svelte-flow__pane');
	const box = (await pane.boundingBox())!;
	const centre = { x: box.width / 2, y: box.height / 2 };
	await (await paletteEntry(page, 'integrity-check')).dragTo(pane, { targetPosition: { x: 40, y: 60 } });
	await expect(empty).toHaveCount(0);
	await (await paletteEntry(page, 'integrity-check')).dragTo(pane, { targetPosition: { x: 40, y: centre.y } });
	await (await paletteEntry(page, 'integrity-check')).dragTo(pane, { targetPosition: { x: centre.x, y: 160 } });
	await connect(page, '01', '03');
	await connect(page, '02', '03');
	await expect(page.getByTestId('flow-summary')).toHaveText('3 steps · 1 join · 0 destructive');
	await page.screenshot({ path: `${EVIDENCE}/us30-flow-chrome-dark.png` });
});

test('empty canvas — template and catalog import lead where they say (FR-008, FR-009)', async ({ page }) => {
	await signIn(page);
	await page.getByTestId('empty-canvas').getByRole('button', { name: 'Import from the task catalog' }).click();
	await expect(page).toHaveURL(/view=catalog/);
	await expect(page.getByRole('heading', { name: 'Task catalog' })).toBeVisible();

	await topBar(page).getByRole('button', { name: 'Flows', exact: true }).click();
	await page.getByTestId('empty-canvas').getByRole('button', { name: 'Start from a template' }).click();
	await expect(page.locator('.svelte-flow__node').first()).toBeVisible();
	await expect(page.getByTestId('empty-canvas')).toHaveCount(0);
});

test('palette — counts, Show N more, unsupported types at the end, search finds collapsed ones (FR-013, FR-014)', async ({ page }) => {
	await signIn(page);
	const palette = page.getByRole('complementary', { name: 'Step types' });
	const security = palette.locator('section[aria-labelledby="cat-security"]');
	await expect(security.locator('.count')).toHaveText(/^\d+$/);
	const total = Number(await security.locator('.count').textContent());
	const more = security.getByRole('button', { name: /^Show \d+ more$/ });
	await expect(more).toBeVisible();
	await expect(security.locator('[data-step-type]')).toHaveCount(3);
	// Keyboard opens it too (FR-004).
	await more.focus();
	await page.keyboard.press('Enter');
	await expect(security.locator('[data-step-type]')).toHaveCount(total);
	// The class name is the secondary text of every entry.
	await expect(security.locator('[data-step-type="certificate-expiry-check"] .entry-class')).toHaveText(
		'sentai.steps.reports.CertificateExpiry'
	);

	const unsupported = palette.locator('section[aria-labelledby="cat-unsupported"]');
	await expect(unsupported.getByRole('heading')).toContainText('types not supported in v1');
	await expect(unsupported.locator('[data-step-type]')).toHaveCount(0);
	await unsupported.getByRole('button', { name: 'Show' }).click();
	for (const type of ['purge-audit-records', 'compact-globals', 'custom']) {
		await expect(unsupported.locator(`[data-step-type="${type}"]`)).toBeDisabled();
		await expect(unsupported.locator(`[data-step-type="${type}"]`)).toContainText('not supported in v1');
	}

	await page.reload();
	await palette.getByLabel('Search step type').fill('oauth');
	await expect(palette.locator('[data-step-type="oauth-inventory"]')).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/us30-palette-dark.png` });
});

test('width — every flow action reachable at 1280 × 800, no horizontal scroll', async ({ page }) => {
	await page.setViewportSize({ width: 1280, height: 800 });
	await signIn(page);
	const bar = flowBar(page);
	for (const name of ['Open…', 'Save', 'Validate', 'Run now', 'Schedule']) {
		await expect(bar.getByRole('button', { name, exact: true })).toBeInViewport();
	}
	await expect(bar.getByRole('button', { name: 'More flow actions' })).toBeInViewport();
	const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
	expect(overflow).toBeLessThanOrEqual(0);
	await page.screenshot({ path: `${EVIDENCE}/us30-flow-chrome-1280.png` });
});

test('accessibility — no serious or critical violation on Flows, dark and light (SC-008)', async ({ page }) => {
	await signIn(page);
	await setTheme(page, 'Dark');
	await expectNoSeriousA11y(page, 'us30-flows-dark');
	await setTheme(page, 'Light');
	await expectNoSeriousA11y(page, 'us30-flows-light');
	await page.screenshot({ path: `${EVIDENCE}/us30-empty-canvas-light.png` });
	await setTheme(page, 'Dark');
});
