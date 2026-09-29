import { describe, expect, it } from 'vitest';
import { cancelRaisesAlert, stepCancelRaisesAlert } from './cancel-alert';
import type { StepRunView } from './run';

// Spec 011 US5: IRIS records a cancelled platform job as a severity-2 alert (docs/limitations.md).
// Only a running step executed through the management API has such a job.
const registry = [
	{ type: 'integrity-check', executor: 'platform-api' as const },
	{ type: 'db-size-report', executor: 'in-process' as const }
];

const flowSteps = [
	{ id: '01', type: 'integrity-check' },
	{ id: '02', type: 'integrity-check', target: 'iris-target' },
	{ id: '03', type: 'db-size-report' },
	{ id: '04', type: 'no-such-type' }
];

const run = (stepId: string, state: StepRunView['state']): Pick<StepRunView, 'stepId' | 'state'> => ({ stepId, state });

describe('stepCancelRaisesAlert', () => {
	it('is true for a running local integrity check', () => {
		expect(stepCancelRaisesAlert(run('01', 'running'), flowSteps, registry)).toBe(true);
	});

	it('is true for a running remote integrity check (the target records its own alert)', () => {
		expect(stepCancelRaisesAlert(run('02', 'running'), flowSteps, registry)).toBe(true);
	});

	it('is false for a queued integrity check (no platform job yet)', () => {
		expect(stepCancelRaisesAlert(run('01', 'queued'), flowSteps, registry)).toBe(false);
	});

	it('is false for a running in-process step', () => {
		expect(stepCancelRaisesAlert(run('03', 'running'), flowSteps, registry)).toBe(false);
	});

	it('is false for a type the registry does not know', () => {
		expect(stepCancelRaisesAlert(run('04', 'running'), flowSteps, registry)).toBe(false);
	});

	it('is false for a step that is not in the flow, or no step run at all', () => {
		expect(stepCancelRaisesAlert(run('99', 'running'), flowSteps, registry)).toBe(false);
		expect(stepCancelRaisesAlert(undefined, flowSteps, registry)).toBe(false);
	});
});

describe('cancelRaisesAlert', () => {
	it('is true when any running step is executed through the management API', () => {
		expect(cancelRaisesAlert([run('03', 'running'), run('01', 'running')], flowSteps, registry)).toBe(true);
	});

	it('is false when the running steps are all in-process or the others are queued or finished', () => {
		expect(
			cancelRaisesAlert([run('03', 'running'), run('01', 'queued'), run('02', 'completed')], flowSteps, registry)
		).toBe(false);
	});

	it('is false with no steps', () => {
		expect(cancelRaisesAlert([], flowSteps, registry)).toBe(false);
	});
});
