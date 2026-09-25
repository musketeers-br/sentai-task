// Theme audits for UI-007: a light value must never be a computed inverse of its dark value,
// and text must meet WCAG contrast in both themes. Pure functions — used by unit and e2e tests.

const HEX = /^#[0-9a-f]{6}$/i;

export function invertHex(hex: string): string {
	const n = Number.parseInt(hex.slice(1), 16);
	return `#${(0xffffff - n).toString(16).padStart(6, '0').toUpperCase()}`;
}

function channel(c: number): number {
	const s = c / 255;
	return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
}

export function relativeLuminance(hex: string): number {
	const n = Number.parseInt(hex.slice(1), 16);
	return 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255);
}

export function contrastRatio(a: string, b: string): number {
	const [hi, lo] = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x);
	return (hi + 0.05) / (lo + 0.05);
}

export interface AuditRow {
	token: string;
	dark: string;
	light: string;
	invertedDark: string;
	/** True when the light value is exactly the inverse of the dark one — a derived theme. */
	derived: boolean;
}

/** Walks the token tree and collects every {dark, light} colour pair, wherever it sits. */
export function auditTokens(tree: unknown): AuditRow[] {
	const rows: AuditRow[] = [];
	const t = tree as { theme?: { dark: Record<string, unknown>; light: Record<string, unknown> } };

	// theme.dark.X / theme.light.X
	if (t.theme) {
		for (const [key, dark] of Object.entries(t.theme.dark)) {
			const light = t.theme.light[key];
			if (typeof dark === 'string' && typeof light === 'string' && HEX.test(dark) && HEX.test(light)) {
				rows.push(row(`theme.${key}`, dark, light));
			}
		}
	}

	// any object carrying {dark: '#…', light: '#…'} elsewhere (state, category, edge, …) —
	// and {dark: {a,b,…}, light: {a,b,…}} objects of colours (timeline segments).
	const visit = (node: unknown, path: string) => {
		if (!node || typeof node !== 'object' || path === 'theme') return;
		const o = node as Record<string, unknown>;
		if (typeof o.dark === 'string' && typeof o.light === 'string' && HEX.test(o.dark) && HEX.test(o.light)) {
			rows.push(row(path, o.dark, o.light));
		} else if (o.dark && o.light && typeof o.dark === 'object' && typeof o.light === 'object') {
			const d = o.dark as Record<string, unknown>;
			const l = o.light as Record<string, unknown>;
			for (const k of Object.keys(d)) {
				if (typeof d[k] === 'string' && typeof l[k] === 'string' && HEX.test(d[k] as string)) {
					rows.push(row(`${path}.${k}`, d[k] as string, l[k] as string));
				}
			}
		}
		for (const [k, v] of Object.entries(o)) visit(v, path ? `${path}.${k}` : k);
	};
	visit(tree, '');
	return rows;
}

function row(token: string, dark: string, light: string): AuditRow {
	const invertedDark = invertHex(dark);
	return { token, dark, light, invertedDark, derived: invertedDark.toUpperCase() === light.toUpperCase() };
}
