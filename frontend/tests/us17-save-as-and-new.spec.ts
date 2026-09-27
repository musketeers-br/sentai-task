/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import { envelope, seedFlow, signIn, token } from './support';

// spec 010 User Story 1 — Save as a new flow, never overwrite by accident (FR-001, FR-004…FR-008).

const EVIDENCE = '../specs/010-canvas-onboarding-usability/evidence';
const API = '/csp/sentai/api/v1';

/** Two read-only steps; enough to tell two flows' contents apart. */
function twoStepFlow(name: string) {
	const step = (id: string, type: string, taskName: string) => ({
		id,
		type,
		taskName,
		namespace: '%SYS',
		wqmCategory: 'Default'
	});
	return {
		name,
		defaultCategory: 'Default',
		steps: [step('01', 'storage-headroom-check', 'Headroom'), step('02', 'db-size-report', 'Sizes')],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 }, '02': { x: 40, y: 260 } } }
	};
}

async function readFlow(request: APIRequestContext, id: string) {
	const res = await request.get(`${API}/flows/${id}`, { headers: { Authorization: `Bearer ${await token(request)}` } });
	expect(res.status(), await res.text()).toBe(200);
	return (await res.json()) as { id: string; name: string; revision: number | string; steps: unknown[] };
}

const flowIdIn = (page: Page) => new URL(page.url()).searchParams.get('flow');
const guard = (page: Page) => page.getByRole('dialog', { name: /^Save changes to / });

/** *New flow* and *Save as…* live in the top bar's *More ▾* menu (plan D-7 fallback at 1440 px). */
async function flowCommand(page: Page, name: 'New flow' | 'Save as…') {
	await page.getByRole('banner').getByRole('button', { name: 'More' }).click();
	await page.getByRole('menuitem', { name }).click();
}

async function addUnsavedStep(page: Page) {
	await page.locator('[data-step-type="db-size-report"]').click();
	await expect(page.getByTestId('flow-meta')).toContainText('edited');
}

test('us17 Save as — a second flow from the canvas; the original keeps its name, revision and contents', async ({ page }) => {
	const ts = Date.now();
	const nameA = `us17-A-${ts}`;
	const nameB = `us17-B-${ts}`;
	const idA = await seedFlow(page.request, twoStepFlow(nameA));
	await signIn(page, `?flow=${idA}`);
	await expect(page.getByLabel('Flow name')).toHaveValue(nameA);

	// An unsaved edit goes to the new flow only (edge case).
	await addUnsavedStep(page);
	await flowCommand(page, 'Save as…');
	const dialog = page.getByRole('dialog', { name: 'Save as a new flow' });
	await expect(dialog).toBeVisible();
	await dialog.getByLabel('Name').fill(nameB);
	await dialog.getByRole('button', { name: 'Save as', exact: true }).click();
	await expect(dialog).toBeHidden();

	await expect(page.getByLabel('Flow name')).toHaveValue(nameB);
	await expect.poll(() => flowIdIn(page)).not.toBe(idA);
	const idB = flowIdIn(page)!;
	await expect(page.getByTestId('flow-meta')).toContainText('rev 1');

	const a = await readFlow(page.request, idA);
	const b = await readFlow(page.request, idB);
	expect(a.name).toBe(nameA);
	expect(Number(a.revision)).toBe(1);
	expect(a.steps).toHaveLength(2);
	expect(b.name).toBe(nameB);
	expect(b.steps).toHaveLength(3);

	// Back returns to the original, untouched.
	await page.goBack();
	await expect(page.getByLabel('Flow name')).toHaveValue(nameA);
	await expect(page.locator('.svelte-flow__node')).toHaveCount(2);

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us17-save-as.json`,
		envelope('us17-save-as', { method: 'POST', path: '/flows' }, { a: { id: idA, name: a.name, revision: a.revision, steps: a.steps.length }, b: { id: idB, name: b.name, revision: b.revision, steps: b.steps.length } }, [
			'Save as created B from the canvas (3 steps, the third unsaved at the time); A kept rev 1 and 2 steps.'
		])
	);
});

test('us17 rename notice — editing a saved flow\'s name says it renames this flow (FR-005)', async ({ page }) => {
	const name = `us17-R-${Date.now()}`;
	const id = await seedFlow(page.request, twoStepFlow(name));
	await signIn(page, `?flow=${id}`);
	const note = page.getByText('Renames this flow — use Save as… to keep a copy');
	await expect(note).toHaveCount(0);
	await page.getByLabel('Flow name').fill(`${name} renamed`);
	await expect(note).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/us17-rename-note.png` });
	await page.getByLabel('Flow name').fill(name);
	await expect(note).toHaveCount(0);
});

test('us17 Save as refused — a taken name shows the platform\'s reason and keeps the dialog open (FR-008)', async ({ page }) => {
	const ts = Date.now();
	const taken = `us17-T-${ts}`;
	await seedFlow(page.request, twoStepFlow(taken));
	const id = await seedFlow(page.request, twoStepFlow(`us17-S-${ts}`));
	await signIn(page, `?flow=${id}`);
	await flowCommand(page, 'Save as…');
	const dialog = page.getByRole('dialog', { name: 'Save as a new flow' });
	await dialog.getByLabel('Name').fill(taken);
	await dialog.getByRole('button', { name: 'Save as', exact: true }).click();
	await expect(dialog.getByRole('alert')).toHaveText('A flow with this name already exists');
	await expect(dialog).toBeVisible();
	await expect(dialog.getByLabel('Name')).toHaveValue(taken);
	await dialog.getByRole('button', { name: 'Cancel' }).click();
	await expect(dialog).toBeHidden();
	expect(flowIdIn(page)).toBe(id);
});

test('us17 New flow — the unsaved-changes guard (Cancel / Discard / Save), then an empty draft (FR-006, FR-007)', async ({ page }) => {
	const name = `us17-N-${Date.now()}`;
	const id = await seedFlow(page.request, twoStepFlow(name));
	await signIn(page, `?flow=${id}`);

	// Cancel keeps everything.
	await addUnsavedStep(page);
	await flowCommand(page, 'New flow');
	await expect(guard(page)).toBeVisible();
	await guard(page).getByRole('button', { name: 'Cancel' }).click();
	await expect(guard(page)).toBeHidden();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(3);
	expect(flowIdIn(page)).toBe(id);

	// Discard clears the canvas; the address no longer names the flow; Back returns to it.
	await flowCommand(page, 'New flow');
	await guard(page).getByRole('button', { name: 'Discard' }).click();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(0);
	await expect(page.getByLabel('Flow name')).toHaveValue(/^Untitled flow \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
	await expect(page.getByTestId('flow-meta')).toHaveText('not saved yet');
	await expect.poll(() => flowIdIn(page)).toBeNull();
	await page.goBack();
	await expect(page.getByLabel('Flow name')).toHaveValue(name);
	await expect(page.locator('.svelte-flow__node')).toHaveCount(2);
	expect(Number((await readFlow(page.request, id)).revision)).toBe(1);

	// Save saves first, then clears.
	await addUnsavedStep(page);
	await flowCommand(page, 'New flow');
	await guard(page).getByRole('button', { name: 'Save', exact: true }).click();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(0);
	await expect.poll(() => flowIdIn(page)).toBeNull();
	const saved = await readFlow(page.request, id);
	expect(Number(saved.revision)).toBe(2);
	expect(saved.steps).toHaveLength(3);

	// No unsaved edits: New flow does not ask.
	await flowCommand(page, 'New flow');
	await expect(guard(page)).toHaveCount(0);
});

test('us17 Save as on a draft — the first save under the entered name (edge case)', async ({ page }) => {
	const name = `us17-D-${Date.now()}`;
	await signIn(page);
	await page.locator('[data-step-type="db-size-report"]').click();
	await flowCommand(page, 'Save as…');
	const dialog = page.getByRole('dialog', { name: 'Save as a new flow' });
	await dialog.getByLabel('Name').fill(name);
	await dialog.getByRole('button', { name: 'Save as', exact: true }).click();
	await expect(dialog).toBeHidden();
	await expect(page.getByLabel('Flow name')).toHaveValue(name);
	await expect.poll(() => flowIdIn(page)).toMatch(/^\d+$/);
	expect((await readFlow(page.request, flowIdIn(page)!)).name).toBe(name);
});

test('us17 revision conflict — the platform\'s words, then a Save as… hint (edge case)', async ({ page }) => {
	const name = `us17-C-${Date.now()}`;
	const id = await seedFlow(page.request, twoStepFlow(name));
	await signIn(page, `?flow=${id}`);

	// Someone else saves the flow meanwhile.
	const current = await readFlow(page.request, id);
	const put = await page.request.put(`${API}/flows/${id}?revision=${current.revision}`, {
		headers: { Authorization: `Bearer ${await token(page.request)}` },
		data: twoStepFlow(name)
	});
	expect(put.status(), await put.text()).toBe(200);

	await addUnsavedStep(page);
	await page.getByRole('button', { name: 'Save flow' }).click();
	await expect(page.getByRole('status').filter({ hasText: 'Flow was saved by someone else since it was loaded' })).toBeVisible();
	await expect(page.getByText('Use Save as… to keep your version.')).toBeVisible();
});

test('us17 top bar — every control fits at 1440 px', async ({ page }) => {
	await signIn(page);
	const fits = await page.evaluate(() => {
		const bar = document.querySelector('header.top-bar') as HTMLElement;
		const box = bar.getBoundingClientRect();
		const clipped = [...bar.querySelectorAll('button, input')]
			.map((el) => ({ el, r: el.getBoundingClientRect() }))
			.filter(({ r }) => r.width > 0 && (r.left < box.left - 0.5 || r.right > box.right + 0.5))
			.map(({ el }) => (el as HTMLElement).innerText || (el as HTMLInputElement).value);
		return { clipped, overflow: bar.scrollWidth - bar.clientWidth };
	});
	expect(fits.clipped).toEqual([]);
	expect(fits.overflow).toBeLessThanOrEqual(0);
	await expect(page.getByRole('banner').getByRole('button', { name: 'Save flow', exact: true })).toBeVisible();
	await page.getByRole('banner').getByRole('button', { name: 'More' }).click();
	await expect(page.getByRole('menu')).toBeVisible();
	await expect(page.getByRole('menuitem')).toHaveText(['New flow', 'Save as…']);
	await page.keyboard.press('Escape');
	await expect(page.getByRole('menu')).toHaveCount(0);
	await expect(page.getByRole('banner').getByRole('button', { name: 'More' })).toBeFocused();
});
