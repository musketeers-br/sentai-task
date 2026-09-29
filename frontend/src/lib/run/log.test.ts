import { describe, expect, it } from 'vitest';
import { chronological, EMPTY_LOG_TEXT, severityLabel } from './log';

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
