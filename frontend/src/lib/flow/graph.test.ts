import { describe, expect, it } from 'vitest';
import { checkConnection, incomingSources, joinTargets, wouldCreateCycle } from './graph';

const canonical = [
	{ source: '01', target: '04' },
	{ source: '02', target: '04' },
	{ source: '03', target: '04' },
	{ source: '04', target: '05' }
];

describe('wouldCreateCycle', () => {
	it('is false for an edge that extends the DAG', () => {
		expect(wouldCreateCycle(canonical, '05', '06')).toBe(false);
	});

	it('is true when the target already reaches the source', () => {
		expect(wouldCreateCycle(canonical, '05', '01')).toBe(true);
	});

	it('is true for a self loop', () => {
		expect(wouldCreateCycle([], '01', '01')).toBe(true);
	});
});

describe('checkConnection (FR-002: rejected at the moment it is drawn)', () => {
	it('accepts a new acyclic edge', () => {
		expect(checkConnection(canonical, '01', '05')).toEqual({ ok: true });
	});

	it('rejects a self loop', () => {
		expect(checkConnection(canonical, '04', '04')).toEqual({ ok: false, reason: 'self' });
	});

	it('rejects a duplicate edge', () => {
		expect(checkConnection(canonical, '01', '04')).toEqual({ ok: false, reason: 'duplicate' });
	});

	it('rejects an edge that would close a cycle', () => {
		expect(checkConnection(canonical, '05', '02')).toEqual({ ok: false, reason: 'cycle' });
	});
});

describe('joins (FR-004)', () => {
	it('lists only targets with two or more incoming edges', () => {
		expect(joinTargets(canonical)).toEqual(['04']);
	});

	it('lists incoming sources in step-id order', () => {
		expect(incomingSources([...canonical].reverse(), '04')).toEqual(['01', '02', '03']);
	});
});
