import { describe, expect, it } from 'vitest';
import { fromWireRun } from '$lib/run/run';
import { fromWireStep, fromWireStepTypes } from '$lib/api/wire';
import type { FlowStep, StepTypeInfo } from '$lib/flow/document';
import { fromWireTarget, fromWireTargetStatus, targetChoices, targetsUsedBy, type TargetView } from './targets';

// Shapes from specs/008-distributed-targets/evidence/quickstart-http-2026-09-27.json.
const wireTarget = {
	name: 'iris-target',
	baseUrl: 'http://iris-target:52773',
	description: 'demo target (compose)',
	createdAt: '2026-09-27 14:16:19',
	updatedAt: '2026-09-27 14:16:19',
	online: true
};

describe('targets view models (spec 009 T001)', () => {
	it('maps a target as the API returned it', () => {
		expect(fromWireTarget(wireTarget)).toEqual({
			name: 'iris-target',
			baseUrl: 'http://iris-target:52773',
			description: 'demo target (compose)',
			online: true
		});
	});

	it('maps a reachable, an unreachable and a refused status verbatim, computing nothing', () => {
		const categories = [{ Name: 'Default', MaxActiveWorkers: 'Dynamic (40)', DefaultWorkers: 'Dynamic (20)', MaxWorkers: 'Dynamic (40)', MaxTotalWorkers: 0, AlwaysQueue: false }];
		expect(
			fromWireTargetStatus({ target: 'iris-target', readAt: '2026-09-27 14:16:21', reachable: true, version: 'IRIS 2026.2', user: '_SYSTEM', categories })
		).toEqual({ kind: 'reachable', readAt: '2026-09-27 14:16:21', version: 'IRIS 2026.2', user: '_SYSTEM', categories });
		expect(
			fromWireTargetStatus({ target: 'iris-target', readAt: 't', reachable: false, unreachable: { transportError: 'ERROR #6059: Unable to open TCP/IP socket to server iris-target:52773' } })
		).toEqual({ kind: 'unreachable', readAt: 't', transportError: 'ERROR #6059: Unable to open TCP/IP socket to server iris-target:52773' });
		expect(
			fromWireTargetStatus({ target: 'iris-target', readAt: 't', reachable: true, refused: { status: 401, title: 'Unauthorized', detail: '', httpStatus: 401 } })
		).toEqual({ kind: 'refused', readAt: 't', text: 'HTTP 401 — no reason given' });
	});

	it('lists the targets a flow uses once each, in step-id order', () => {
		const step = (id: string, target?: string) => ({ id, ...(target ? { target } : {}) }) as FlowStep;
		expect(targetsUsedBy([step('03', 'b'), step('01'), step('02', 'a'), step('04', 'b')])).toEqual(['a', 'b']);
		expect(targetsUsedBy([step('01')])).toEqual([]);
	});

	it('offers online targets only for a remote-capable type', () => {
		const targets: TargetView[] = [
			{ name: 'a', baseUrl: 'https://a:1', description: '', online: true },
			{ name: 'b', baseUrl: 'https://b:1', description: '', online: false }
		];
		const info = (remoteCapable: boolean) => ({ type: 'x', remoteCapable }) as StepTypeInfo;
		expect(targetChoices(targets, info(true)).map((t) => t.name)).toEqual(['a']);
		expect(targetChoices(targets, info(false))).toEqual([]);
		expect(targetChoices(targets, undefined)).toEqual([]);
	});
});

describe('wire additions (spec 009 T001)', () => {
	const base = { id: '03', type: 'integrity-check', taskName: 't', namespace: 'USER' };

	it('keeps a step target, and leaves it absent for a local step', () => {
		expect(fromWireStep({ ...base, target: 'iris-target' }).target).toBe('iris-target');
		expect('target' in fromWireStep(base)).toBe(false);
	});

	it('maps remoteCapable, failing closed when absent', () => {
		const [capable, missing] = fromWireStepTypes([
			{ type: 'integrity-check', class: 'c', category: 'verification', destructive: false, pausable: false, available: true, remoteCapable: true },
			{ type: 'db-size-report', class: 'c', category: 'verification', destructive: false, pausable: false, available: true }
		]);
		expect(capable.remoteCapable).toBe(true);
		expect(missing.remoteCapable).toBeFalsy();
	});

	it('maps executedOn from the run read', () => {
		const run = fromWireRun({
			guid: 'g', flowId: '1', flowRevision: 1, state: 'running', startedAt: '2026-09-27 14:16:40', finishedAt: '', dispatchedBy: '_SYSTEM',
			steps: [
				{ guid: 's1', stepId: '01', state: 'running', timeQueued: '2026-09-27 14:16:40', executedOn: 'local', executedAs: '' },
				{ guid: 's3', stepId: '03', state: 'running', timeQueued: '2026-09-27 14:16:40', executedOn: 'iris-target', executedAs: '_SYSTEM' }
			]
		});
		expect(run.steps.find((s) => s.stepId === '03')?.executedOn).toBe('iris-target');
		expect(run.steps.find((s) => s.stepId === '03')?.executedAs).toBe('_SYSTEM');
		expect(run.steps.find((s) => s.stepId === '01')?.executedOn).toBe('local');
	});
});
