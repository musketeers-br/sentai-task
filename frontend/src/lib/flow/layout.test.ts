import { describe, expect, it } from 'vitest';
import { autoLayout } from './layout';

describe('autoLayout', () => {
	it('places each step in the column of its longest path from a root', () => {
		const positions = autoLayout(
			['01', '02', '03', '04', '05'],
			[
				{ source: '01', target: '04' },
				{ source: '02', target: '04' },
				{ source: '03', target: '04' },
				{ source: '04', target: '05' }
			]
		);
		expect(positions['01'].x).toBe(positions['03'].x);
		expect(positions['04'].x).toBeGreaterThan(positions['01'].x);
		expect(positions['05'].x).toBeGreaterThan(positions['04'].x);
		expect(new Set([positions['01'].y, positions['02'].y, positions['03'].y]).size).toBe(3);
	});

	it('keeps positions the flow already has', () => {
		const positions = autoLayout(['01', '02'], [], { '01': { x: 5, y: 7 } });
		expect(positions['01']).toEqual({ x: 5, y: 7 });
		expect(positions['02']).toBeDefined();
	});
});
