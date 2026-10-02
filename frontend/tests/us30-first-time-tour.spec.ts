/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { envelope, signInAt } from './support';
import { contrastFailures } from './theming';

// spec 021 User Story 1 — the three coach marks, taken from the Tour button
// (FR-001…FR-005, FR-009, FR-010, SC-001). The guide stays dismissed (support.ts's seed), which
// is exactly the point: the tour never opens by itself and the guide is not involved.

const EVIDENCE = '../specs/021-first-time-tour/evidence';

const tourButton = (page: Page) => page.getByTestId('tour-button');
const tour = (page: Page) => page.getByRole('dialog', { name: 'Tour' });

async function onCanvas(page: Page) {
	await signInAt(page);
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
}

/** True when the two elements' boxes overlap — the spotlight sits on its anchor (FR-003). */
async function overlaps(page: Page, spotlight: string, anchor: string): Promise<boolean> {
	return page.evaluate(
		([a, b]) => {
			const box = (sel: string) => {
				const el = document.querySelector(sel);
				if (!el) return null;
				const r = el.getBoundingClientRect();
				return { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
			};
			const s = box(a);
			const t = box(b);
			return s !== null && t !== null && s.left < t.right && s.right > t.left && s.top < t.bottom && s.bottom > t.top;
		},
		[spotlight, anchor]
	);
}

test('us30 button — Tour on the Flows screen only; one action; never opens by itself (FR-001, FR-009)', async ({ page }) => {
	await onCanvas(page);
	await expect(tourButton(page)).toBeVisible();
	await expect(tour(page)).toHaveCount(0); // FR-009: no automatic opening, ever

	for (const tab of ['Overview', 'Task catalog', 'Targets', 'Runs']) {
		await page.getByRole('button', { name: tab, exact: true }).click();
		await expect(tourButton(page)).toHaveCount(0);
	}
	await page.getByRole('button', { name: 'Flows', exact: true }).click();
	await expect(tourButton(page)).toBeVisible();
});

test('us30 marks — three marks in order, each spotlighting its anchor; Done ends; reopening identical (FR-002…FR-005, FR-010, SC-001)', async ({ page }) => {
	mkdirSync(EVIDENCE, { recursive: true });
	await onCanvas(page);

	await tourButton(page).click();
	await expect(tour(page)).toBeVisible();
	await expect(tour(page).getByTestId('tour-indicator')).toHaveText('1 of 3');
	await expect(tour(page).getByTestId('tour-mark-body')).toHaveText('This is the palette — drag a step onto the canvas.');
	await expect
		.poll(() => overlaps(page, '[data-testid="tour-spotlight"]', 'aside[aria-label="Step types"]'), { message: 'spotlight on the palette' })
		.toBe(true);
	await page.screenshot({ path: `${EVIDENCE}/us30-tour-mark1-dark.png` });

	await tour(page).getByRole('button', { name: 'Next' }).click();
	await expect(tour(page).getByTestId('tour-indicator')).toHaveText('2 of 3');
	await expect(tour(page).getByTestId('tour-mark-body')).toHaveText('Connect two steps to create a dependency.');
	await expect
		.poll(() => overlaps(page, '[data-testid="tour-spotlight"]', '.canvas[role="application"]'), { message: 'spotlight on the connection surface' })
		.toBe(true);
	await page.screenshot({ path: `${EVIDENCE}/us30-tour-mark2-dark.png` });

	await tour(page).getByRole('button', { name: 'Next' }).click();
	await expect(tour(page).getByTestId('tour-indicator')).toHaveText('3 of 3');
	await expect(tour(page).getByTestId('tour-mark-body')).toHaveText('Validate the flow, then run it.');
	await expect
		.poll(() => overlaps(page, '[data-testid="tour-spotlight"]', '[data-tour-target="validate"]'), { message: 'spotlight covers Validate flow' })
		.toBe(true);
	await expect
		.poll(() => overlaps(page, '[data-testid="tour-spotlight"]', '[data-tour-target="run"]'), { message: 'spotlight covers Run now' })
		.toBe(true);
	await expect(tour(page).getByRole('button', { name: 'Next' })).toHaveCount(0);
	await page.screenshot({ path: `${EVIDENCE}/us30-tour-mark3-dark.png` });

	await tour(page).getByRole('button', { name: 'Done' }).click();
	await expect(tour(page)).toHaveCount(0);

	// FR-010: reopening is identical — nothing was remembered, nothing needs clearing.
	// Skip is the every-mark dismissal control (FR-005); the tour is at mark 1 again.
	await tourButton(page).click();
	await expect(tour(page).getByTestId('tour-indicator')).toHaveText('1 of 3');
	await expect(tour(page).getByTestId('tour-mark-body')).toHaveText('This is the palette — drag a step onto the canvas.');
	await tour(page).getByRole('button', { name: 'Skip' }).click();
	await expect(tour(page)).toHaveCount(0);

	// Light-theme evidence for the theming table (the page is inert while the tour is open,
	// so the theme switch happens between tours, not during one).
	await page.getByRole('button', { name: 'Light', exact: true }).click();
	await tourButton(page).click();
	await expect(tour(page).getByTestId('tour-indicator')).toHaveText('1 of 3');
	await page.screenshot({ path: `${EVIDENCE}/us30-tour-mark1-light.png` });
	await tour(page).getByRole('button', { name: 'Skip' }).click();
	await expect(tour(page)).toHaveCount(0);

	writeFileSync(
		`${EVIDENCE}/us30-tour.json`,
		envelope(
			'us30-tour',
			{ ui: 'Canvas tour' },
			{
				marks: [
					'This is the palette — drag a step onto the canvas.',
					'Connect two steps to create a dependency.',
					'Validate the flow, then run it.'
				]
			},
			['The three marks, in the order contracts/tour.md §3 declares them.']
		)
	);
});

test('us30 keyboard — a modal dialog named Tour; focus starts inside; Tab wraps; Escape skips; focus returns (FR-005, FR-006, SC-003)', async ({ page }) => {
	await onCanvas(page);
	await tourButton(page).click();
	const dialog = tour(page);
	await expect(dialog).toBeVisible();
	await expect(page.locator('dialog[open]')).toHaveAttribute('aria-modal', 'true');
	await expect(dialog).toHaveAccessibleName('Tour');
	// Focus starts inside the tour (data-model §4).
	expect(await page.evaluate(() => document.activeElement?.closest('dialog[open]') !== null)).toBe(true);
	for (let i = 0; i < 15; i++) {
		await page.keyboard.press('Tab');
		expect(await page.evaluate(() => document.activeElement?.closest('dialog[open]') !== null), `Tab #${i + 1}`).toBe(true);
	}
	// Escape has the same effect as Skip from any mark — this one, mark 2.
	await dialog.getByRole('button', { name: 'Next' }).click();
	await expect(dialog.getByTestId('tour-indicator')).toHaveText('2 of 3');
	await page.keyboard.press('Escape');
	await expect(dialog).toHaveCount(0);
	// Focus returns to the Tour button, the element that had it when the tour opened.
	await expect(tourButton(page)).toBeFocused();
});

test('us30 skip — Skip on mark 1 ends it at once, the canvas is usable, and the next start is identical (FR-005, FR-010)', async ({ page }) => {
	await onCanvas(page);
	await tourButton(page).click();
	await tour(page).getByRole('button', { name: 'Skip' }).click();
	await expect(tour(page)).toHaveCount(0);
	// The canvas is fully usable immediately: a palette click still adds a step.
	await page.locator('[data-step-type]').first().click();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(1);
	// Nothing was remembered against the operator: the next start is identical.
	await tourButton(page).click();
	await expect(tour(page).getByTestId('tour-indicator')).toHaveText('1 of 3');
	await tour(page).getByRole('button', { name: 'Skip' }).click();
	await expect(tour(page)).toHaveCount(0);
});

test('us30 coexistence — the spec 010 guide is untouched; nothing automatic opens during a tour (FR-008, FR-009, scenarios 3.1–3.4)', async ({ page }) => {
	// A fresh browser: the guide opens automatically exactly as spec 010 defines it (scenario 3.1).
	await signInAt(page, '', undefined, undefined, { guide: 'fresh' });
	const guideDialog = page.getByRole('dialog', { name: 'Getting started' });
	await expect(guideDialog).toBeVisible();
	await guideDialog.getByRole('button', { name: 'Close' }).click();
	await expect(guideDialog).toHaveCount(0);

	// While the tour is open, exactly one dialog is open — nothing automatic stacks (scenario 3.3).
	await tourButton(page).click();
	await expect(tour(page)).toBeVisible();
	expect(await page.locator('dialog[open]').count()).toBe(1);
	await tour(page).getByRole('button', { name: 'Skip' }).click();

	// Help → Getting started still opens the six-step guide at step 1 (scenario 3.4).
	await page.getByRole('banner').getByRole('button', { name: 'Help' }).click();
	await page.getByRole('menuitem', { name: 'Getting started' }).click();
	await expect(guideDialog).toBeVisible();
	await expect(guideDialog.getByText('Step 1 of 6')).toBeVisible();
	await guideDialog.getByRole('button', { name: 'Close' }).click();
});

test('us30 gallery — the runbook gallery stays under the tour and after it (FR-007, spec 022 FR-015)', async ({ page }) => {
	await onCanvas(page);
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();
	await tourButton(page).click();
	await expect(tour(page)).toBeVisible();
	await expect(page.getByTestId('runbook-gallery')).toBeAttached();
	await tour(page).getByRole('button', { name: 'Skip' }).click();
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();
});

test('us30 close rule — a navigation away from the editable canvas ends the tour; no ghost on return (FR-011)', async ({ page }) => {
	// Land on Task catalog first, so Back from the Flows screen is a real screen change.
	await signInAt(page, '?view=catalog');
	await expect(tourButton(page)).toHaveCount(0);
	await page.getByRole('button', { name: 'Flows', exact: true }).click();
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();

	await tourButton(page).click();
	await expect(tour(page)).toBeVisible();

	// The page behind the modal is inert, but browser Back still works — the one way an
	// operator leaves the canvas mid-tour. The tour must end with the screen change…
	await page.goBack();
	await expect(tour(page)).toHaveCount(0);
	// …and returning to the canvas must not resurrect it as a ghost.
	await page.getByRole('button', { name: 'Flows', exact: true }).click();
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	await expect(tour(page)).toHaveCount(0);
});

test('us30 small viewport — every mark shows its card fully inside the viewport (spec edge case)', async ({ page }) => {
	await page.setViewportSize({ width: 1024, height: 640 });
	await onCanvas(page);
	await tourButton(page).click();
	for (let i = 0; i < 3; i++) {
		await expect(tour(page).getByTestId('tour-indicator')).toHaveText(`${i + 1} of 3`);
		const inside = await page.evaluate(() => {
			const vw = window.innerWidth;
			const vh = window.innerHeight;
			const card = document.querySelector('.tour .card')?.getBoundingClientRect();
			const spot = document.querySelector('[data-testid="tour-spotlight"]')?.getBoundingClientRect();
			return {
				cardInside: !!card && card.left >= 0 && card.top >= 0 && card.right <= vw && card.bottom <= vh,
				spotlightVisible: !!spot && spot.width > 0 && spot.height > 0
			};
		});
		expect(inside.cardInside, `mark ${i + 1}: the card never leaves 1024×640`).toBe(true);
		expect(inside.spotlightVisible, `mark ${i + 1}: the spotlight is drawn`).toBe(true);
		if (i < 2) await tour(page).getByRole('button', { name: 'Next' }).click();
	}
	await tour(page).getByRole('button', { name: 'Done' }).click();
	await expect(tour(page)).toHaveCount(0);
});

test('us30 theming and fit — the card reads in both themes; the 1440 px top bar is exactly as before (T016)', async ({ page }) => {
	await onCanvas(page);
	const failures: Record<string, unknown> = {};
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		await tourButton(page).click();
		await page.mouse.move(0, 0);
		const found = await contrastFailures(page);
		if (found.length > 0) failures[theme] = found;
		await tour(page).getByRole('button', { name: 'Skip' }).click();
		await expect(tour(page)).toHaveCount(0);
	}
	expect(failures, 'every text ≥ 4.5:1 (≥ 3:1 at ≥ 24 px)').toEqual({});

	// The Tour button lives on the canvas, so the bar keeps its exact pre-021 fit (plan R-4).
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
});
