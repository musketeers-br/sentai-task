/// <reference types="node" />
import { mkdirSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { catalog, detail } from './catalog-support';
import { seedFlow, signIn, signInAt, token } from './support';
import { contrastFailures } from './theming';

// spec 007 SC-008 / FR-020 — the catalog screen in both themes, with the same assertions as spec
// 002 Q10: same structure and strings, readable text in each. (Part B's parameter-form pair is
// added with T008/T010.)

const EVIDENCE = '../specs/007-canvas-management-screens/evidence';

async function structure(page: Page) {
	const height = async (sel: string) => Math.round((await page.locator(sel).first().boundingBox())!.height);
	return {
		topBar: await height('.top-bar'),
		rows: await catalog(page).getByTestId('catalog-row').count(),
		seals: await page.getByTestId('destructive-seal').count(),
		suspended: await page.getByTestId('suspended-mark').count(),
		detailWidth: Math.round((await detail(page).boundingBox())!.width),
		texts: (await page.evaluate(() => document.body.innerText))
			.split('\n')
			.map((s) => s.trim())
			// The freshness clock ticks between the two captures.
			.filter((s) => s && !/^updated \d+ s ago$/.test(s))
	};
}

test('us13-management-theming — the catalog with a destructive task open reads the same in both themes', async ({ page }) => {
	const res = await page.request.get('/csp/sentai/api/v1/catalog/tasks?destructiveOnly=1', {
		headers: { Authorization: `Bearer ${await token(page.request)}` }
	});
	const destructive = (await res.json()).items[0];
	expect(destructive, 'the instance has a destructive task').toBeTruthy();

	await signInAt(page, `?view=catalog&task=${destructive.taskId}`);
	await expect(detail(page).getByTestId('detail-field-destructive')).toHaveText('destructive');
	await expect(catalog(page).getByTestId('catalog-row').first()).toBeVisible();

	mkdirSync(EVIDENCE, { recursive: true });
	const shots: Record<string, Awaited<ReturnType<typeof structure>>> = {};
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', theme.toLowerCase());
		await page.mouse.move(0, 0);
		shots[theme] = await structure(page);
		expect(await contrastFailures(page), `${theme}: every text ≥ 4.5:1 (≥ 3:1 at ≥ 24 px)`).toEqual([]);
		await page.screenshot({ path: `${EVIDENCE}/sc008-catalog-${theme.toLowerCase()}.png` });
	}

	expect(shots.Light).toEqual(shots.Dark);
	for (const s of ['Flows', 'Task catalog', 'sorted by next run', 'Destructive only', 'DESTRUCTIVE']) {
		expect(shots.Dark.texts.join('\n'), s).toContain(s);
	}
});

test('us13-management-theming — the parameter form with a field in error reads the same in both themes', async ({ page }) => {
	const id = await seedFlow(page.request, {
		name: `us13 params ${Date.now()}`,
		defaultCategory: 'Default',
		steps: [{ id: '01', type: 'storage-headroom-check', taskName: 'Storage headroom', namespace: '%SYS', runAsUser: 'irisadm', wqmCategory: 'Default', parameters: { minFreePercent: 150 } }],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	});
	await signIn(page, `?flow=${id}`);
	await page.locator('.svelte-flow__node[data-id="01"] h3').click();
	await page.getByRole('button', { name: 'Validate flow' }).click();
	const inspector = page.getByLabel('Inspector', { exact: true });
	await expect(inspector.getByTestId('param-error-minFreePercent')).toBeVisible();

	mkdirSync(EVIDENCE, { recursive: true });
	const texts: Record<string, string[]> = {};
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', theme.toLowerCase());
		await page.mouse.move(0, 0);
		expect(await contrastFailures(page), `${theme}: every text >= 4.5:1`).toEqual([]);
		texts[theme] = await inspector.locator('h2, label, .param, [data-testid="param-error-minFreePercent"]').allInnerTexts();
		await page.screenshot({ path: `${EVIDENCE}/sc008-params-${theme.toLowerCase()}.png` });
	}
	expect(texts.Light).toEqual(texts.Dark);
});
