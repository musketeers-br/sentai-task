/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { envelope, expandPalette, flowButton, seedFlow, signIn, token } from './support';

// spec 007 User Story 5 — declared custom steps in the canvas (Part B, T007/T008), built in the
// existing visual system (spec 009 Clarifications Q1, which also unblocks this part).

const EVIDENCE = '../specs/007-canvas-management-screens/evidence';
const customGroup = (page: Page) => page.locator('section[aria-labelledby="cat-custom"]');
const inspector = (page: Page) => page.getByLabel('Inspector', { exact: true });

async function catalog(page: Page) {
	const res = await page.request.get('/csp/sentai/api/v1/catalog/step-types', { headers: { Authorization: `Bearer ${await token(page.request)}` } });
	return (await res.json()) as Array<{ type: string; label: string; executor: string; available: boolean; parameters?: unknown[] }>;
}

test('us11 custom group — the in-process types from the API plus legacy custom, with the API labels', async ({ page }) => {
	await signIn(page);
	const types = await catalog(page);
	const declared = types.filter((t) => t.executor === 'in-process' || t.type === 'custom');
	// Spec 023 FR-013: the group lists its available types (collapsed past three until opened);
	// the unsupported ones, legacy custom included, are gathered in the trailing group.
	await expandPalette(page);
	const expected = declared.filter((t) => t.available);
	const entries = customGroup(page).locator('[data-step-type]');
	await expect(entries).toHaveCount(expected.length);
	for (const [i, t] of expected.entries()) {
		await expect(entries.nth(i)).toHaveAttribute('data-step-type', t.type);
		await expect(entries.nth(i).locator('.entry-name')).toHaveText(t.label);
	}
	const unsupported = page.locator('section[aria-labelledby="cat-unsupported"]');
	for (const t of declared.filter((d) => !d.available)) {
		await expect(unsupported.locator(`[data-step-type="${t.type}"]`)).toBeDisabled();
		await expect(unsupported.locator(`[data-step-type="${t.type}"]`)).toContainText('not supported in v1');
	}
	await expect(unsupported.locator('[data-step-type="custom"]')).toBeDisabled();
});

test('us11 parameter form — fields from the schema; an out-of-range value is reported on its field', async ({ page }) => {
	const id = await seedFlow(page.request, {
		name: `us11 params ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [
			{ id: '01', type: 'storage-headroom-check', taskName: 'Storage headroom', namespace: '%SYS', runAsUser: 'irisadm', wqmCategory: 'Default' },
			{ id: '02', type: 'db-size-report', taskName: 'DB sizes', namespace: '%SYS', runAsUser: 'irisadm', wqmCategory: 'Default' }
		],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 }, '02': { x: 40, y: 260 } } }
	});
	await signIn(page, `?flow=${id}`);

	await page.locator('.svelte-flow__node[data-id="02"] h3').click();
	await expect(inspector(page).getByTestId('no-parameters')).toHaveText('This step type takes no parameters.');

	await page.locator('.svelte-flow__node[data-id="01"] h3').click();
	const fields = inspector(page).getByTestId('param-field');
	await expect(fields).toHaveCount(1);
	const input = inspector(page).getByLabel('MinFreePercent');
	await expect(input).toHaveAttribute('type', 'number');
	await expect(input).toHaveAttribute('placeholder', 'default: 10');
	await expect(input).toHaveValue('');
	await expect(fields.first()).toContainText('0–100');
	await expect(fields.first()).toContainText('Fail when any database or journal location has less free space than this percentage');

	await input.fill('150');
	await flowButton(page, 'save').click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');
	const validated = page.waitForResponse((r) => r.url().endsWith(`/flows/${id}/validate`));
	await flowButton(page, 'validate').click();
	const report = await (await validated).json();
	const finding = report.errors.find((f: { code: string }) => f.code === 'PARAM_OUT_OF_RANGE');
	expect(finding?.parameter).toBe('minFreePercent');
	await expect(inspector(page).getByTestId('param-error-minFreePercent')).toHaveText(finding.message);
	await expect(page.getByTestId('status-errors')).toContainText('#01');

	// Cleared: the key is removed and the backend applies the default (R-7).
	await input.fill('');
	await flowButton(page, 'save').click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 3');
	const res = await page.request.get(`/csp/sentai/api/v1/flows/${id}`, { headers: { Authorization: `Bearer ${await token(page.request)}` } });
	expect((await res.json()).steps.find((s: { id: string }) => s.id === '01').parameters).toEqual({});

	mkdirSync(EVIDENCE, { recursive: true });
	writeFileSync(
		`${EVIDENCE}/us5-params.json`,
		envelope('us5-params', { method: 'POST', path: `/flows/${id}/validate` }, { status: 200, body: report }, [
			'storage-headroom-check: one field (minFreePercent, number, 0–100, placeholder "default: 10", description from the API).',
			`PARAM_OUT_OF_RANGE carried parameter "${finding.parameter}" and was shown on that field, verbatim (field level).`,
			'db-size-report: "This step type takes no parameters." Clearing the field removed the key.'
		])
	);
});
