import { describe, expect, it } from 'vitest';
import { buildRunExport, exportFileName } from './export';
import type { RunView } from './run';

const run = (state: RunView['state']): RunView => ({
	guid: '09121AD9-B8DC-11F1-A8F9-F6B706D1754E',
	flowId: '8',
	flowRevision: 3,
	state,
	startedAt: '2026-09-29 10:00:00',
	finishedAt: state === 'running' ? null : '2026-09-29 10:01:00',
	dispatchedBy: '_SYSTEM',
	steps: [
		{
			guid: 'a',
			stepId: '01',
			state: 'failed',
			timeQueued: 'q',
			timeStarted: 's',
			timeFinished: 'f',
			failureReason: 'ERROR #5002: verbatim',
			progressCurrent: null,
			progressTotal: null,
			executedOn: 'iris-target',
			executedAs: '_SYSTEM',
			result: { databases: [{ name: 'USER' }] }
		}
	],
	log: [
		{ at: '2', stepId: null, severity: 'error', message: 'Run failed' },
		{ at: '1', stepId: null, severity: 'info', message: 'Run dispatched' }
	]
});

describe('buildRunExport', () => {
	it('carries the run, every step with its result and reason, and the log oldest first', () => {
		const out = buildRunExport(run('failed'), 'Nightly checks', new Date('2026-09-29T10:02:00Z'));
		expect(out.format).toBe('sentai-run-export/1');
		expect(out.exportedAt).toBe('2026-09-29T10:02:00.000Z');
		expect(out.flow).toEqual({ id: '8', name: 'Nightly checks', revision: 3 });
		expect(out.steps[0].failureReason).toBe('ERROR #5002: verbatim');
		expect(out.steps[0].result).toEqual({ databases: [{ name: 'USER' }] });
		expect(out.log.map((l) => l.message)).toEqual(['Run dispatched', 'Run failed']);
		expect(out).not.toHaveProperty('exportedWhile');
	});

	it('marks a run exported while it was running', () => {
		expect(buildRunExport(run('running'), 'F', new Date()).exportedWhile).toBe('running');
	});

	it('holds nothing from the session', () => {
		const text = JSON.stringify(buildRunExport(run('completed'), 'F', new Date()));
		expect(text).not.toMatch(/token|password|refresh/i);
	});
});

describe('exportFileName', () => {
	it('slugs the flow name and uses the first 8 characters of the guid', () => {
		expect(exportFileName('Example: storage health check', '09121AD9-B8DC')).toBe('Example-storage-health-check-09121AD9.json');
		expect(exportFileName('%%%', 'ABCDEFGH-1')).toBe('run-ABCDEFGH.json');
	});
});
