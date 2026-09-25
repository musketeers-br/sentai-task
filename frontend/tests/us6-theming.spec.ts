import { readFileSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { auditTokens } from '../src/lib/design/audit';
import { canonicalFlow, EVIDENCE_DIR, seedFlow, signIn } from './support';

// spec.md User Story 6 / UI-007 — the light theme is designed, not derived (Q10). Differential:
// same structure and strings in both themes, contrast in both, no light token = inverse(dark).

/** Everything UI-007 says must NOT change between themes. */
async function structure(page: Page) {
	const box = async (sel: string) => {
		const b = (await page.locator(sel).first().boundingBox())!;
		return { w: Math.round(b.width), h: Math.round(b.height) };
	};
	return {
		topBar: (await box('.top-bar')).h,
		palette: (await box('[aria-label="Step types"]')).w,
		inspector: (await box('[aria-label="Inspector"]')).w,
		statusBar: (await box('.status-bar')).h,
		nodes: await page.locator('.svelte-flow__node').count(),
		edges: await page.locator('.svelte-flow__edge').count(),
		junctions: await page.locator('[data-junction-for]').count(),
		hazardBands: await page.getByTestId('hazard-band').count(),
		seals: await page.getByTestId('destructive-seal').count(),
		inspectorSections: (await page.getByLabel('Inspector', { exact: true }).locator('h2').allTextContents()).map((s) =>
			s.trim()
		),
		texts: (await page.evaluate(() => document.body.innerText)).split('\n').map((s) => s.trim()).filter(Boolean)
	};
}

/** WCAG 2.1 contrast for every visible text node, against its effective background. */
async function contrastFailures(page: Page) {
	return page.evaluate(() => {
		const parse = (c: string) => {
			let m = c.match(/^rgba?\(([^)]+)\)$/);
			if (m) {
				const [r, g, b, a = 1] = m[1].split(/[\s,/]+/).filter(Boolean).map(Number);
				return { r, g, b, a };
			}
			m = c.match(/^color\(srgb ([^)]+)\)$/);
			if (m) {
				const [r, g, b, a = 1] = m[1].split(/[\s/]+/).filter(Boolean).map(Number);
				return { r: r * 255, g: g * 255, b: b * 255, a };
			}
			return null;
		};
		const lum = ({ r, g, b }: { r: number; g: number; b: number }) =>
			[r, g, b]
				.map((v) => v / 255)
				.map((s) => (s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4))
				.reduce((acc, v, i) => acc + v * [0.2126, 0.7152, 0.0722][i], 0);
		const background = (el: Element | null) => {
			for (let e = el; e; e = e.parentElement) {
				const c = parse(getComputedStyle(e).backgroundColor);
				if (c && c.a >= 0.5) return c;
			}
			return parse(getComputedStyle(document.body).backgroundColor)!;
		};

		const failures: Array<{ text: string; ratio: number; required: number; where: string }> = [];
		const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
		for (let n = walker.nextNode(); n; n = walker.nextNode()) {
			const text = n.textContent?.trim();
			const el = n.parentElement;
			if (!text || !el) continue;
			const r = el.getBoundingClientRect();
			const cs = getComputedStyle(el);
			if (r.width === 0 || r.height === 0 || cs.visibility === 'hidden' || cs.display === 'none') continue;
			if (el.closest('button:disabled, [aria-disabled="true"], [disabled], dialog:not([open])')) continue;
			const fg = parse(cs.color);
			if (!fg) continue;
			const bg = background(el);
			const [hi, lo] = [lum(fg), lum(bg)].sort((a, b) => b - a);
			const ratio = (hi + 0.05) / (lo + 0.05);
			const required = parseFloat(cs.fontSize) >= 24 ? 3 : 4.5;
			if (ratio < required) {
				failures.push({ text: text.slice(0, 40), ratio: Math.round(ratio * 100) / 100, required, where: el.className?.toString().slice(0, 50) ?? el.tagName });
			}
		}
		return failures;
	});
}

test('Q10 — both themes render the same screen, each with its own palette and readable text', async ({ page, request }) => {
	const id = await seedFlow(request, canonicalFlow(`Q10 theming ${Date.now()}`));
	await signIn(page, `?flow=${id}`);
	await page.locator('.svelte-flow__node[data-id="04"] h3').click();
	await page.getByRole('button', { name: 'Validate flow' }).click();
	await expect(page.getByTestId('status-errors')).toBeVisible();

	const shots: Record<string, Awaited<ReturnType<typeof structure>>> = {};
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		await expect(page.locator('html')).toHaveAttribute('data-theme', theme.toLowerCase());
		await page.mouse.move(0, 0);
		shots[theme] = await structure(page);
		expect(await contrastFailures(page), `${theme}: every text ≥ 4.5:1 (≥ 3:1 at ≥ 24 px)`).toEqual([]);
		await page.screenshot({ path: `${EVIDENCE_DIR}/q10-theming-${theme.toLowerCase()}.png` });
	}

	// UI-007: identical except colour, elevation and selection treatment.
	expect(shots.Light).toEqual(shots.Dark);
	expect(shots.Dark.inspectorSections).toEqual(['SELECTED STEP', 'IDENTIFICATION', 'PARAMETERS', 'DESTRUCTIVE STEP', 'OUTPUT']);
	for (const s of ['STEP TYPES', 'Validate flow', 'Schedule in Task Manager', 'Dark', 'Light', 'sequence', 'join (fan-in)']) {
		expect(shots.Dark.texts.join('\n'), s).toContain(s);
	}

	// Elevation inverts (UI-007 §1): the canvas is the darkest surface in dark, the lightest in light.
	// Resolved through a probe element, so minified spellings (#fff vs #FFFFFF) don't matter.
	const canvasColour = async () =>
		page.evaluate(() => {
			const probe = document.createElement('div');
			probe.style.background = 'var(--canvas-ground)';
			document.body.append(probe);
			const colour = getComputedStyle(probe).backgroundColor;
			probe.remove();
			return colour;
		});
	expect(await canvasColour()).toBe('rgb(255, 255, 255)');
	await page.getByRole('button', { name: 'Dark', exact: true }).click();
	expect(await canvasColour()).toBe('rgb(10, 13, 19)');

	// UI-007 step 5: no light token equals the inverse of its dark token.
	const tokens = JSON.parse(readFileSync('../specs/002-canvas-ui/contracts/tokens.json', 'utf-8'));
	const rows = auditTokens(tokens);
	writeFileSync(
		`${EVIDENCE_DIR}/q10-token-audit.json`,
		JSON.stringify(
			{
				evidence_id: 'q10-token-audit',
				captured_at: new Date().toISOString(),
				rule: 'UI-007 step 5 — a light value must never equal the channel-wise inverse of its dark value',
				pairs: rows.length,
				derived: rows.filter((r) => r.derived).length,
				rows
			},
			null,
			2
		)
	);
	expect(rows.filter((r) => r.derived)).toEqual([]);
});
