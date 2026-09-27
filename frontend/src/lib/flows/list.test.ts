import { describe, expect, it } from 'vitest';
import { defaultFlowName, filterByName, orderBySaved, type FlowSummaryView } from './list';

describe('defaultFlowName (spec 010 FR-007)', () => {
	const now = new Date(2026, 8, 27, 10, 11, 12);

	it('names a new flow after the local date and time, to the second', () => {
		expect(defaultFlowName(now, [])).toBe('Untitled flow 2026-09-27 10:11:12');
	});

	it('adds (2), (3)… while the name is taken, ignoring case', () => {
		expect(defaultFlowName(now, ['untitled FLOW 2026-09-27 10:11:12'])).toBe('Untitled flow 2026-09-27 10:11:12 (2)');
		expect(
			defaultFlowName(now, ['Untitled flow 2026-09-27 10:11:12', 'Untitled flow 2026-09-27 10:11:12 (2)'])
		).toBe('Untitled flow 2026-09-27 10:11:12 (3)');
	});
});

const row = (id: string, name: string, savedAt: string | null): FlowSummaryView => ({ id, name, revision: 1, savedAt });

describe('orderBySaved (spec 010 FR-002)', () => {
	it('puts the most recently saved first, never-dated last, and breaks ties by name', () => {
		const list = [
			row('1', 'b', '2026-09-26 09:00:00'),
			row('2', 'x', null),
			row('3', 'c', '2026-09-27 08:00:00'),
			row('4', 'a', '2026-09-26 09:00:00')
		];
		expect(orderBySaved(list).map((r) => r.id)).toEqual(['3', '4', '1', '2']);
	});

	it('does not reorder its input', () => {
		const list = [row('1', 'a', '2026-01-01 00:00:00'), row('2', 'b', '2026-02-01 00:00:00')];
		orderBySaved(list);
		expect(list.map((r) => r.id)).toEqual(['1', '2']);
	});
});

describe('filterByName (spec 010 FR-002)', () => {
	const list = [row('1', 'Nightly Checks', null), row('2', 'weekly purge', null)];

	it('keeps names containing the text, ignoring case and surrounding spaces', () => {
		expect(filterByName(list, '  CHECK ').map((r) => r.id)).toEqual(['1']);
		expect(filterByName(list, 'ly').map((r) => r.id)).toEqual(['1', '2']);
	});

	it('an empty filter keeps everything, and the input is not changed', () => {
		expect(filterByName(list, '')).toEqual(list);
		expect(filterByName(list, '   ')).toHaveLength(2);
		expect(list).toHaveLength(2);
	});
});
