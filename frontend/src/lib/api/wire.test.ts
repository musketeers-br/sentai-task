import { describe, expect, it } from 'vitest';
import {
	fromWireFlow,
	fromWireFlowSummary,
	fromWireStepSearch,
	fromWireStepTypes,
	type WireFlow
} from './wire';

// Shapes copied from specs/003-backend-objectscript/evidence/quickstart-http-20260923.json
const wireFlow: WireFlow = {
	id: '1445',
	name: 'Quickstart-20260923010013',
	revision: 1,
	savedAt: '2026-09-23 04:00:13',
	savedBy: '_SYSTEM',
	defaultCategory: 'Default',
	steps: [
		{
			id: '04',
			type: 'purge-audit-records',
			taskName: 'Purge audit',
			namespace: '%SYS',
			databaseDirectory: '',
			runAsUser: 'irisadm',
			timeoutMinutes: 20,
			wqmCategory: 'Default',
			customClass: '',
			isDestructive: '1'
		},
		{
			id: '01',
			type: 'integrity-check',
			taskName: 'IC USER',
			namespace: 'USER',
			databaseDirectory: '/usr/irissys/mgr/user/',
			runAsUser: 'irisadm',
			timeoutMinutes: '',
			wqmCategory: 'Default',
			customClass: '',
			isDestructive: '0'
		}
	],
	edges: [{ source: '01', target: '04' }],
	joins: [],
	canvasGeometry: ''
};

describe('fromWireFlow', () => {
	it('accepts the empty-string canvasGeometry the backend returns for a flow saved without one', () => {
		expect(fromWireFlow(wireFlow).positions).toEqual({});
	});

	it('orders steps by id and maps an empty timeout to null', () => {
		const doc = fromWireFlow(wireFlow);
		expect(doc.steps.map((s) => s.id)).toEqual(['01', '04']);
		expect(doc.steps[0].timeoutMinutes).toBeNull();
		expect(doc.steps[1].timeoutMinutes).toBe(20);
	});

	it('reads a stored timeout of 0 as "no timeout" — the backend stores an omitted timeout as 0', () => {
		const doc = fromWireFlow({
			...wireFlow,
			steps: [{ ...wireFlow.steps[0], timeoutMinutes: 0 }]
		});
		expect(doc.steps[0].timeoutMinutes).toBeNull();
	});

	it('drops isDestructive — the client derives it from the registry, never from a stored flag', () => {
		const doc = fromWireFlow(wireFlow);
		expect('isDestructive' in doc.steps[0]).toBe(false);
	});

	it('keeps saved node positions', () => {
		const doc = fromWireFlow({ ...wireFlow, canvasGeometry: { nodes: { '01': { x: 10, y: 20 } } } });
		expect(doc.positions).toEqual({ '01': { x: 10, y: 20 } });
	});
});

describe('fromWireStepTypes', () => {
	it('maps the registry entry, renaming class to className', () => {
		expect(
			fromWireStepTypes([
				{ type: 'custom', class: '', category: 'custom', destructive: false, pausable: false, available: false }
			])
		).toEqual([
			{ type: 'custom', className: '', category: 'custom', destructive: false, pausable: false, available: false }
		]);
	});

	it('carries spec 004 availability, and only an explicit true counts as available', () => {
		const [ic, legacy] = fromWireStepTypes([
			{ type: 'integrity-check', class: '%SYS.Task.IntegrityCheck', category: 'verification', destructive: false, pausable: false, available: true },
			{ type: 'switch-journal', class: '%SYS.Task.SwitchJournal', category: 'journal', destructive: false, pausable: false }
		]);
		expect(ic.available).toBe(true);
		expect(legacy.available).toBe(false);
	});
});

describe('fromWireFlowSummary (spec 010 FR-002)', () => {
	it('keeps id, name, revision and savedAt as GET /flows reports them', () => {
		// Shape probed on 2026-09-27 (spec 010 research R-1).
		expect(
			fromWireFlowSummary({ id: '95', name: 'A', revision: 1, savedAt: '2026-09-26 09:29:13', savedBy: 'tester', nextRun: '' })
		).toEqual({ id: '95', name: 'A', revision: 1, savedAt: '2026-09-26 09:29:13' });
	});

	it('tolerates a string revision and an empty or absent savedAt', () => {
		expect(fromWireFlowSummary({ id: '3', name: 'B', revision: '4', savedAt: '' })).toEqual({
			id: '3',
			name: 'B',
			revision: 4,
			savedAt: null
		});
		expect(fromWireFlowSummary({ id: '3', name: 'B', revision: '' })).toEqual({ id: '3', name: 'B', revision: 0, savedAt: null });
	});
});

describe('fromWireStepSearch (spec 011)', () => {
	it('maps an available body, keeping the API’s order and scores', () => {
		expect(
			fromWireStepSearch({
				available: true,
				matches: [
					{ type: 'switch-journal', score: 0.79 },
					{ type: 'integrity-check', score: 0.42 }
				]
			})
		).toEqual({
			available: true,
			matches: [
				{ type: 'switch-journal', score: 0.79 },
				{ type: 'integrity-check', score: 0.42 }
			]
		});
	});

	it('carries each documented reason through verbatim', () => {
		for (const reason of ['not-configured', 'unreachable', 'slow', 'incompatible', 'error']) {
			expect(fromWireStepSearch({ available: false, reason })).toEqual({
				available: false,
				reason
			});
		}
	});

	it('maps an unrecognised reason to error — a reason the contract does not name is still a reason, never a throw', () => {
		expect(fromWireStepSearch({ available: false, reason: 'on-fire' })).toEqual({
			available: false,
			reason: 'error'
		});
		expect(fromWireStepSearch({ available: false })).toEqual({ available: false, reason: 'error' });
	});

	it('maps a malformed body to error rather than throwing into the component', () => {
		// Both answers are 200, so anything that is neither shape is a defect — but FR-023 still
		// says a malformed server answer must degrade the palette, not become an error state.
		expect(fromWireStepSearch(null)).toEqual({ available: false, reason: 'error' });
		expect(fromWireStepSearch('nope')).toEqual({ available: false, reason: 'error' });
		expect(fromWireStepSearch({ available: true })).toEqual({ available: false, reason: 'error' });
		expect(fromWireStepSearch({ available: true, matches: 'x' })).toEqual({
			available: false,
			reason: 'error'
		});
	});

	it('drops a match without a usable type or score instead of offering it as a ranked result', () => {
		expect(
			fromWireStepSearch({
				available: true,
				matches: [
					// Kept: wire.ts tolerates the backend's numbers-as-strings (see the header), like
					// fromWireFlow does for `revision`.
					{ type: 'switch-journal', score: '0.79' },
					// Dropped: a match that names nothing renderable or carries no score.
					{ type: '', score: 0.9 },
					{ type: 'integrity-check', score: 'high' },
					{ type: 'purge-task-history' }
				]
			})
		).toEqual({ available: true, matches: [{ type: 'switch-journal', score: 0.79 }] });
	});
});
