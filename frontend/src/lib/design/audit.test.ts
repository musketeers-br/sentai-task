import { describe, expect, it } from 'vitest';
import { auditTokens, contrastRatio, invertHex } from './audit';
import { tokens } from './tokens';

describe('invertHex', () => {
	it('inverts each channel', () => {
		expect(invertHex('#0A0D13')).toBe('#F5F2EC');
	});
});

describe('contrastRatio (WCAG 2.1)', () => {
	it('is 21:1 for black on white and 1:1 for equal colours', () => {
		expect(contrastRatio('#000000', '#FFFFFF')).toBeCloseTo(21, 5);
		expect(contrastRatio('#123456', '#123456')).toBeCloseTo(1, 5);
	});
});

describe('UI-007 step 5 — no light token is the inverse of its dark token', () => {
	const rows = auditTokens(tokens);

	it('audits every themed colour pair in tokens.json', () => {
		// 16 theme + 6 state + 6 stateText + 6 category + 5 destructive + 5 warning + 4 edge +
		// 3 timeline. A new themed token must show up here, or the audit has a blind spot.
		expect(rows.length).toBe(51);
	});

	it('finds no derived light value', () => {
		expect(rows.filter((r) => r.derived)).toEqual([]);
	});
});
