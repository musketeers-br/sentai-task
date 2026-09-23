import { describe, expect, it } from 'vitest';
import { fromWireFlow, fromWireStepTypes, type WireFlow } from './wire';

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
				{ type: 'custom', class: '', category: 'custom', destructive: false, pausable: false }
			])
		).toEqual([{ type: 'custom', className: '', category: 'custom', destructive: false, pausable: false }]);
	});
});
