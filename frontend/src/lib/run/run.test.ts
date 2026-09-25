import { describe, expect, it } from 'vitest';
import {
	countLine,
	failedJoins,
	formatClock,
	formatDuration,
	fromWireRun,
	parseServerTime,
	stepDurationMs
} from './run';

// Shapes as GET /runs/{guid} returned them on the dev instance (2026-09-25).
const wire = {
	guid: '09121AD9-B8DC-11F1-A8F9-F6B706D1754E',
	flowId: '8',
	flowRevision: 1,
	state: 'running',
	startedAt: '2026-09-25 12:24:20',
	finishedAt: '',
	dispatchedBy: '_SYSTEM',
	steps: [
		{ guid: 'a', stepId: '03', state: 'failed', timeQueued: '2026-09-25 12:24:20', timeStarted: '2026-09-25 12:25:13', timeFinished: '2026-09-25 12:26:30', failureReason: 'Administrative endpoint /x returned HTTP 401', progressCurrent: '', progressTotal: '' },
		{ guid: 'b', stepId: '01', state: 'completed', timeQueued: '2026-09-25 12:24:20', timeStarted: '2026-09-25 12:24:21', timeFinished: '2026-09-25 12:25:12', failureReason: '', progressCurrent: '', progressTotal: '' },
		{ guid: 'c', stepId: '03', state: 'running', timeQueued: '2026-09-25 12:27:00', timeStarted: '2026-09-25 12:27:01', timeFinished: '', failureReason: '', progressCurrent: 3, progressTotal: 10 },
		{ guid: 'd', stepId: '04', state: 'queued', timeQueued: '2026-09-25 12:24:20', timeStarted: '', timeFinished: '', failureReason: '', progressCurrent: '', progressTotal: '' }
	],
	log: []
};

describe('parseServerTime', () => {
	it('reads the backend timestamp as UTC', () => {
		expect(parseServerTime('2026-09-25 12:24:20')).toBe(Date.UTC(2026, 8, 25, 12, 24, 20));
	});

	it('maps an empty value to null', () => {
		expect(parseServerTime('')).toBeNull();
		expect(parseServerTime(null)).toBeNull();
	});
});

describe('fromWireRun', () => {
	it('keeps only the latest StepRun of a re-run step, ordered by step id', () => {
		const run = fromWireRun(wire);
		expect(run.steps.map((s) => `${s.stepId}:${s.guid}`)).toEqual(['01:b', '03:c', '04:d']);
	});

	it('normalizes empty strings to null and keeps failure reasons verbatim', () => {
		const run = fromWireRun({ ...wire, steps: [wire.steps[0]] });
		expect(run.finishedAt).toBeNull();
		expect(run.steps[0].progressTotal).toBeNull();
		expect(run.steps[0].failureReason).toBe('Administrative endpoint /x returned HTTP 401');
	});
});

describe('countLine (FR-024 verbatim format)', () => {
	it('matches the UI-002 wording', () => {
		const states = ['completed', 'completed', 'failed', 'running', 'queued'] as const;
		expect(countLine(states.map((state) => ({ state })))).toBe(
			'2 completed · 1 failed · 1 running · 1 queued'
		);
	});

	it('appends paused and cancelled only when present', () => {
		expect(countLine([{ state: 'completed' }, { state: 'cancelled' }])).toBe(
			'1 completed · 0 failed · 0 running · 0 queued · 1 cancelled'
		);
	});
});

describe('durations', () => {
	it('formats a step duration like UI-002 (12:04.7)', () => {
		expect(formatDuration(12 * 60_000 + 4_700)).toBe('12:04.7');
		expect(formatDuration(51_000)).toBe('00:51.0');
	});

	it('formats the wave clock as hh:mm:ss', () => {
		expect(formatClock(24 * 60_000 + 17_000)).toBe('00:24:17');
	});

	it('measures a finished step from its own start/finish, a running one up to "now"', () => {
		const run = fromWireRun(wire);
		expect(stepDurationMs(run.steps[0], 0)).toBe(51_000);
		expect(stepDurationMs(run.steps[1], Date.UTC(2026, 8, 25, 12, 27, 11))).toBe(10_000);
		expect(stepDurationMs(run.steps[2], Date.now())).toBeNull();
	});
});

describe('failedJoins (FR-028)', () => {
	it('names each join whose required input failed', () => {
		const edges = [
			{ source: '01', target: '04' },
			{ source: '02', target: '04' },
			{ source: '03', target: '04' },
			{ source: '04', target: '05' }
		];
		const states = { '01': 'completed', '02': 'completed', '03': 'failed', '04': 'queued' } as const;
		expect(failedJoins(edges, (id) => states[id as keyof typeof states])).toEqual([
			{ target: '04', failedInputs: ['03'] }
		]);
	});
});
