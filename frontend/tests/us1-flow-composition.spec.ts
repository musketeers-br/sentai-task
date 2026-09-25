import { expect, test } from '@playwright/test';
import { canonicalFlow, connect, edge, EVIDENCE_DIR, hexToRgb, seedFlow, signIn } from './support';

// spec.md User Story 1 — Flow Composition (Q1 + Q2).

test('Q1 — composes the canonical graph from the palette, with one shared fan-in junction', async ({ page }) => {
	await signIn(page);
	await page.getByLabel('Flow name').fill(`Q1 composition ${Date.now()}`);

	// Scenario 1: dragging a step type onto the canvas creates a node.
	const pane = page.locator('.svelte-flow__pane');
	// Laid out for the 872 px canvas left between the palette and the inspector at 1440 px.
	const drops: Array<[string, number, number]> = [
		['integrity-check', 24, 60],
		['integrity-check', 24, 260],
		['integrity-check', 24, 460],
		['purge-audit-records', 320, 260],
		['switch-journal', 608, 290]
	];
	for (const [type, x, y] of drops) {
		await page.locator(`[data-step-type="${type}"]`).dragTo(pane, { targetPosition: { x, y } });
	}
	await expect(page.locator('.svelte-flow__node')).toHaveCount(5);
	await expect(page.locator('.svelte-flow__node[data-id="01"] article')).toHaveCSS(
		'border-left-color',
		hexToRgb(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--category-verification')))
	);

	// Scenario 2: three edges into #04 converge into ONE diamond junction.
	for (const [from, to] of [['01', '04'], ['02', '04'], ['03', '04'], ['04', '05']]) {
		await connect(page, from, to);
		await expect(edge(page, from, to)).toHaveCount(1);
	}
	await expect(page.locator('[data-junction-for]')).toHaveCount(1);
	await expect(page.locator('[data-junction-for="04"]')).toHaveCount(1);

	// FR-005: join edges 2.5px, sequence edges 1.5px.
	const widths = await page.$$eval('.svelte-flow__edge-path', (paths) =>
		paths.map((p) => ({ join: p.classList.contains('edge-join'), width: getComputedStyle(p).strokeWidth }))
	);
	expect(widths.filter((w) => w.join).map((w) => w.width)).toEqual(['2.5px', '2.5px', '2.5px']);
	expect(widths.filter((w) => !w.join).map((w) => w.width)).toEqual(['1.5px']);

	await expect(page.getByTestId('flow-summary')).toHaveText('5 steps · 1 join · 1 destructive');

	// FR-002: an edge that would close a cycle is refused at the moment it is drawn.
	await connect(page, '05', '01');
	await expect(edge(page, '05', '01')).toHaveCount(0);
	await expect(page.getByRole('status')).toContainText('would create a cycle');
	await page.getByRole('button', { name: 'Dismiss message' }).click();

	await page.screenshot({ path: `${EVIDENCE_DIR}/q1-flow-composition.png` });

	// The composed flow persists: first save creates it (rev 1) and puts its id in the URL.
	await page.getByRole('button', { name: 'Save flow' }).click();
	await expect(page).toHaveURL(/[?&]flow=\d+/);
	await expect(page.getByTestId('flow-meta')).toContainText('rev 1');
});

test('Q2 — a destructive join node carries its full anatomy', async ({ page, request }) => {
	const id = await seedFlow(request, canonicalFlow(`Q2 anatomy ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	const purge = page.locator('.svelte-flow__node[data-id="04"]');
	await expect(purge).toBeVisible();

	// FR-011 / Scenario 3: hazard band + DESTRUCTIVE seal, only on the destructive step.
	await expect(purge.getByTestId('hazard-band')).toBeVisible();
	await expect(purge.getByTestId('destructive-seal')).toHaveText('DESTRUCTIVE');
	await expect(page.getByTestId('hazard-band')).toHaveCount(1);

	// FR-007: left border = step-type category colour, never a state colour.
	const purgeToken = await page.evaluate(() =>
		getComputedStyle(document.documentElement).getPropertyValue('--category-purge')
	);
	await expect(purge.locator('article')).toHaveCSS('border-left-color', hexToRgb(purgeToken));

	// FR-006: title + #NN, namespace chip, parameters, divider, timeout and WQM category.
	await expect(purge).toContainText('Purge audit records');
	await expect(purge).toContainText('#04');
	await expect(purge).toContainText('%SYS');
	await expect(purge).toContainText('DaysToKeep = 30 · irreversible');
	await expect(purge).toContainText('timeout 20 min');
	await expect(purge).toContainText('wqm: Default');
	await expect(purge).toContainText('join: waits for #01 #02 #03');
	await expect(purge.locator('.svelte-flow__handle.target')).toHaveClass(/handle-join/);

	const user = page.locator('.svelte-flow__node[data-id="01"]');
	// Non-ASCII survives the HTTP round trip (the API must read request bodies as UTF-8).
	await expect(user).toContainText('Integrity check — USER');
	await expect(user).toContainText('/usr/irissys/mgr/user/');
	await expect(user).toContainText('timeout 90 min');
	await expect(user.locator('.svelte-flow__handle.target')).toHaveClass(/handle-plain/);

	await expect(page.getByTestId('flow-summary')).toHaveText('5 steps · 1 join · 1 destructive');
	await page.screenshot({ path: `${EVIDENCE_DIR}/q2-node-anatomy.png` });
});
