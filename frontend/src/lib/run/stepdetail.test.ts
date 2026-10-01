import { describe, expect, it } from 'vitest';
import { buildStepDetail, resultCopyText } from './stepdetail';
import { sliceFor } from './log';
import type { LogEntry, StepRunView } from './run';
import { hasResult } from './result';

// Spec 016 US2: the step execution detail the rail renders. Facts come from the run read
// (StepRunView, the latest attempt) and the run's log; nothing is invented (FR-011).

const base: StepRunView = {
	guid: 'g-1',
	stepId: '02',
	state: 'failed',
	timeQueued: '2026-09-29 10:00:00',
	timeStarted: '2026-09-29 10:00:05',
	timeFinished: '2026-09-29 10:00:12',
	failureReason: "ERROR #5001: Storage headroom below 100%: '/data/' has 27.6% free",
	progressCurrent: null,
	progressTotal: null,
	executedOn: 'local',
	executedAs: '_SYSTEM',
	result: null
};

const log: LogEntry[] = [
	// API order: newest first. Two attempts of #02, one run-level, one of #01.
	{ at: '2026-09-29 10:00:20.000', stepId: '01', severity: 'info', message: 'run ended' },
	{ at: '2026-09-29 10:00:12.000', stepId: '02', severity: 'error', message: 'second attempt failed' },
	{ at: '2026-09-29 10:00:08.000', stepId: null, severity: 'info', message: 'operator asked to re-run' },
	{ at: '2026-09-29 10:00:06.000', stepId: '02', severity: 'error', message: 'first attempt failed' }
];

describe('buildStepDetail', () => {
	it('maps the run read facts: state, times, duration, place, identity, reason verbatim', () => {
		const d = buildStepDetail(base, 'Headroom', log, Date.parse('2026-09-29T10:00:20Z'));
		expect(d.stepId).toBe('02');
		expect(d.taskName).toBe('Headroom');
		expect(d.state).toBe('failed');
		expect(d.timeQueued).toBe('2026-09-29 10:00:00');
		expect(d.timeStarted).toBe('2026-09-29 10:00:05');
		expect(d.timeFinished).toBe('2026-09-29 10:00:12');
		expect(d.durationMs).toBe(7000);
		expect(d.executedOn).toBe('local');
		expect(d.executedAs).toBe('_SYSTEM');
		expect(d.failureReason).toBe(base.failureReason);
	});

	it('shows the result the step stored, and says a step without one has none', () => {
		const withResult = { ...base, result: { minFreePercent: 100, locations: [{ path: '/data/', ok: false }] } };
		const d = buildStepDetail(withResult, 'Headroom', log, 0);
		expect(hasResult(d.state, d.result)).toBe(true);
		const without = buildStepDetail({ ...base, state: 'completed', failureReason: null }, 'Headroom', log, 0);
		expect(hasResult(without.state, without.result)).toBe(false);
	});

	it('keeps only that step\'s log entries, all attempts, in time order (FR-010)', () => {
		const d = buildStepDetail(base, 'Headroom', log, 0);
		expect(d.logSlice.map((e) => e.message)).toEqual(['first attempt failed', 'second attempt failed']);
		expect(sliceFor(log, '02').map((e) => e.message)).toEqual(d.logSlice.map((e) => e.message));
	});

	it('invents nothing for a step that has not started (FR-011)', () => {
		const queued: StepRunView = {
			...base,
			stepId: '03', // a step that never ran: no entries anywhere in the log
			state: 'queued',
			timeQueued: '2026-09-29 10:00:00',
			timeStarted: null,
			timeFinished: null,
			failureReason: null,
			// The wire normalizes an empty place to "local"; a step that never ran shows no place.
			executedOn: 'local',
			executedAs: '',
			result: null
		};
		const d = buildStepDetail(queued, 'Never starts', log, 0);
		expect(d.timeStarted).toBeNull();
		expect(d.timeFinished).toBeNull();
		expect(d.durationMs).toBeNull();
		expect(d.executedOn).toBeNull();
		expect(d.executedAs).toBeNull();
		expect(d.failureReason).toBeNull();
		expect(d.logSlice).toEqual([]);
	});

	it('derives the task name fallback from the step id when the flow has none', () => {
		const d = buildStepDetail(base, undefined, log, 0);
		expect(d.taskName).toBe('#02');
	});
});

describe('resultCopyText', () => {
	it('copies the stored JSON exactly, pretty-printed (SC-002)', () => {
		const result = { databases: [{ name: 'USER', sizeMB: 512 }] };
		expect(resultCopyText(result)).toBe(JSON.stringify(result, null, 2));
	});

	it('copies the empty result as an empty object, never as a lie', () => {
		expect(resultCopyText({})).toBe('{}');
	});
});
