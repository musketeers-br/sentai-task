import { describe, expect, it } from 'vitest';
import { chronological, EMPTY_LOG_TEXT, severityLabel, sliceFor } from './log';

const entry = (message: string, at = '2026-09-29 10:00:00.000') => ({ at, stepId: null, severity: 'info', message });

describe('chronological', () => {
	it('reverses the API order (newest first) into reading order, keeping ties', () => {
		const api = [entry('3', '2026-09-29 10:00:01.000'), entry('2b'), entry('2a'), entry('1', '2026-09-29 09:59:59.000')];
		expect(chronological(api).map((e) => e.message)).toEqual(['1', '2a', '2b', '3']);
	});

	it('does not change its input', () => {
		const api = [entry('b'), entry('a')];
		chronological(api);
		expect(api.map((e) => e.message)).toEqual(['b', 'a']);
	});
});

describe('severityLabel', () => {
	it('labels by text, not only by colour', () => {
		expect(severityLabel('info')).toBe('INFO');
		expect(severityLabel('warning')).toBe('WARN');
		expect(severityLabel('error')).toBe('ERROR');
		expect(severityLabel('anything')).toBe('INFO');
	});
});

describe('empty log', () => {
	it('explains runs from before the log existed', () => {
		expect(EMPTY_LOG_TEXT).toBe('No log was recorded for runs before this version.');
	});
});

// Spec 016 FR-010: a selected step narrows the log to its entries — every attempt, in order.

describe('sliceFor', () => {
	const ofStep = (stepId: string | null, message: string, at: string) => ({ at, stepId, severity: 'info', message });
	const api = [
		ofStep('01', 'late run-level', '2026-09-29 10:00:05.000'),
		// API order is newest first: #02's second attempt is the newest entry.
		ofStep('02', 'second attempt', '2026-09-29 10:00:04.000'),
		ofStep(null, 'operator re-ran #02', '2026-09-29 10:00:03.000'),
		ofStep('01', 'unrelated step', '2026-09-29 10:00:02.000'),
		ofStep('02', 'first attempt', '2026-09-29 10:00:01.000')
	];

	it('keeps only that step\'s entries, all attempts, chronological', () => {
		expect(sliceFor(api, '02').map((e) => e.message)).toEqual(['first attempt', 'second attempt']);
	});

	it('excludes run-level entries and other steps', () => {
		const slice = sliceFor(api, '02');
		expect(slice.some((e) => e.stepId === null)).toBe(false);
		expect(slice.some((e) => e.stepId === '01')).toBe(false);
	});

	it('an empty slice is honest about it', () => {
		expect(sliceFor(api, '99')).toEqual([]);
		expect(sliceFor([], '02')).toEqual([]);
	});
});
