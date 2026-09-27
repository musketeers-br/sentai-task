import type { Page } from '@playwright/test';

// Shared by the theming e2e tests (spec 002 Q10, spec 007 SC-008).

/** WCAG 2.1 contrast for every visible text node, against its effective background. */
export async function contrastFailures(page: Page) {
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
