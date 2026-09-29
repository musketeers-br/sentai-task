import { describe, expect, it } from 'vitest';
import { fromWireStepTypes } from '$lib/api/wire';
import { createStep, paletteGroups, typeLabel, type ParameterSpec, type StepTypeInfo } from './document';
import type { Finding } from './report';
import { fieldsFor, routeFindings, writeParameter } from './params';

// Catalog entries as GET /catalog/step-types returns them (spec 005 api-delta; live 2026-09-27).
const wireCatalog = [
	{ type: 'integrity-check', label: 'Integrity check', class: '%SYS.Task.IntegrityCheck', category: 'verification', executor: 'platform-api', destructive: false, pausable: false, available: true, remoteCapable: true },
	{ type: 'switch-journal', label: 'Switch journal', class: '%SYS.Task.SwitchJournal', category: 'journal', executor: 'in-process', destructive: false, pausable: false, available: true, parameters: [] },
	{ type: 'purge-task-history', label: 'Purge task history', class: '%SYS.Task.PurgeTaskHistory', category: 'purge', executor: 'in-process', destructive: true, pausable: false, available: true,
		parameters: [{ name: 'keepDays', property: 'KeepDays', type: 'integer', required: false, default: 30, min: 0, description: 'Days of task history to keep' }] },
	{ type: 'storage-headroom-check', label: 'Storage headroom check', class: 'sentai.steps.StorageHeadroomCheck', category: 'storage', executor: 'in-process', destructive: false, pausable: false, available: true,
		parameters: [{ name: 'minFreePercent', property: 'MinFreePercent', type: 'number', required: false, default: 10, min: 0, max: 100, description: 'Fail when any database or journal location has less free space than this percentage' }] },
	{ type: 'db-size-report', label: 'Database size report', class: 'sentai.steps.DatabaseSizeReport', category: 'verification', executor: 'in-process', destructive: false, pausable: false, available: true, parameters: [] },
	{ type: 'custom', label: 'Custom (legacy)', class: '', category: 'custom', executor: 'platform-api', destructive: false, pausable: false, available: false }
];
const registry = fromWireStepTypes(wireCatalog);
const info = (type: string) => registry.find((t) => t.type === type)!;

describe('step types from the API (spec 007 T007)', () => {
	it('maps label, executor and parameters, without the backend-only property', () => {
		const t = info('storage-headroom-check');
		expect(t.label).toBe('Storage headroom check');
		expect(t.executor).toBe('in-process');
		expect(t.parameters).toEqual([
			{ name: 'minFreePercent', type: 'number', required: false, default: 10, min: 0, max: 100, description: 'Fail when any database or journal location has less free space than this percentage' }
		]);
		expect(info('db-size-report').parameters).toEqual([]);
	});

	it('still maps a pre-005 catalog: no label, no executor, no parameters', () => {
		const [old] = fromWireStepTypes([{ type: 'integrity-check', class: 'c', category: 'verification', destructive: false, pausable: false, available: true }]);
		expect(old.label).toBeUndefined();
		expect(old.parameters).toBeUndefined();
		expect(typeLabel(old)).toBe('Integrity check');
	});

	it('groups in-process types with legacy custom under Custom; the others by category', () => {
		const groups = paletteGroups(registry);
		expect(groups.map((g) => g.id)).toEqual(['verification', 'custom']);
		expect(groups.find((g) => g.id === 'custom')!.types.map((t) => t.type)).toEqual(['switch-journal', 'purge-task-history', 'storage-headroom-check', 'db-size-report', 'custom']);
		expect(groups.find((g) => g.id === 'verification')!.types.map((t) => t.type)).toEqual(['integrity-check']);
	});

	it('spec 013: report types go by their category (Security, Monitoring), never under Custom', () => {
		const withReports = fromWireStepTypes([
			...wireCatalog,
			{ type: 'security-posture-report', label: 'Security posture report', class: 'sentai.steps.reports.SecurityPosture', category: 'security', executor: 'platform-read', destructive: false, pausable: false, available: true, remoteCapable: true, parameters: [] },
			{ type: 'system-alerts-check', label: 'System alerts check', class: 'sentai.steps.reports.SystemAlerts', category: 'monitoring', executor: 'platform-read', destructive: false, pausable: false, available: true, remoteCapable: true, parameters: [] }
		]);
		const groups = paletteGroups(withReports);
		expect(groups.map((g) => g.id)).toEqual(['verification', 'security', 'monitoring', 'custom']);
		expect(groups.find((g) => g.id === 'security')!.types.map((t) => t.executor)).toEqual(['platform-read']);
	});

	it('names a new step after the API label and copies no default for a declared schema (R-7)', () => {
		const step = createStep(info('storage-headroom-check'), '01', 'Default');
		expect(step.taskName).toBe('Storage headroom check');
		expect(step.parameters).toEqual({});
	});
});

const spec = (partial: Partial<ParameterSpec> & Pick<ParameterSpec, 'name' | 'type'>): ParameterSpec => ({ required: false, description: '', ...partial });

describe('parameter form model (spec 007 T008)', () => {
	it('builds one field per declared parameter, for each of the four types', () => {
		const fields = fieldsFor(
			[
				spec({ name: 'label', type: 'string', required: true, description: 'A name' }),
				spec({ name: 'keepDays', type: 'integer', default: 30, min: 0 }),
				spec({ name: 'minFreePercent', type: 'number', default: 10, min: 0, max: 100 }),
				spec({ name: 'dryRun', type: 'boolean' })
			],
			{ keepDays: 7 }
		);
		expect(fields.map((f) => [f.name, f.control, f.required, f.bounds, f.placeholder, f.value])).toEqual([
			['label', 'text', true, '', '', ''],
			['keepDays', 'integer', false, '≥ 0', 'default: 30', '7'],
			['minFreePercent', 'number', false, '0–100', 'default: 10', ''],
			['dryRun', 'checkbox', false, '', '', false]
		]);
		expect(fields[0].label).toBe('Label');
		expect(fields[0].help).toBe('A name');
	});

	it('writes numbers as numbers, booleans as booleans, text as is, and removes a cleared key', () => {
		const base = { keepDays: 7, other: 'x' };
		expect(writeParameter(base, spec({ name: 'keepDays', type: 'integer' }), '12')).toEqual({ keepDays: 12, other: 'x' });
		expect(writeParameter(base, spec({ name: 'minFreePercent', type: 'number' }), '12.5')).toEqual({ ...base, minFreePercent: 12.5 });
		expect(writeParameter(base, spec({ name: 'dryRun', type: 'boolean' }), true)).toEqual({ ...base, dryRun: true });
		expect(writeParameter(base, spec({ name: 'label', type: 'string' }), 'hello')).toEqual({ ...base, label: 'hello' });
		expect(writeParameter(base, spec({ name: 'keepDays', type: 'integer' }), '')).toEqual({ other: 'x' });
		// Not a number: sent as typed, so the API reports it (the browser checks nothing).
		expect(writeParameter(base, spec({ name: 'keepDays', type: 'integer' }), 'abc')).toEqual({ keepDays: 'abc', other: 'x' });
	});

	it('puts a finding on the field its structured parameter names', () => {
		const findings: Finding[] = [{ stepId: '01', code: 'PARAM_OUT_OF_RANGE', parameter: 'minFreePercent', message: "Step '01' (storage-headroom-check): parameter 'minFreePercent' must be between 0 and 100" }];
		const routed = routeFindings(findings, [spec({ name: 'minFreePercent', type: 'number' })]);
		expect(routed.byField.get('minFreePercent')).toEqual([findings[0].message]);
		expect(routed.stepLevel).toEqual([]);
	});

	it('shows the others at step level, verbatim, never reading the message to route', () => {
		const withoutParameter = { stepId: '01', code: 'PARAM_REQUIRED', get message() { return "parameter 'minFreePercent' is required"; } } as Finding;
		const unknown: Finding = { stepId: '01', code: 'PARAM_UNKNOWN', parameter: 'path', message: "unknown parameter 'path'" };
		let reads = 0;
		const spy = new Proxy(withoutParameter, { get: (t, k) => { if (k === 'message') reads++; return Reflect.get(t, k); } });
		const routed = routeFindings([spy, unknown], [spec({ name: 'minFreePercent', type: 'number' })]);
		expect(routed.byField.size).toBe(0);
		expect(routed.stepLevel).toEqual(["parameter 'minFreePercent' is required", "unknown parameter 'path'"]);
		expect(reads).toBe(1); // read once, to display it — never to decide where it goes
	});

	it('shows an unknown type as a read-only row, never as a text input', () => {
		const [field] = fieldsFor([{ name: 'odd', type: 'date' as ParameterSpec['type'], required: false, description: '' }], { odd: '2026-01-01' });
		expect(field.control).toBe('readonly');
		expect(field.value).toBe('2026-01-01');
	});
});

// Type usage check: a StepTypeInfo without the new fields still compiles.
const legacy: StepTypeInfo = { type: 'x', className: '', category: 'custom', destructive: false, pausable: false, available: false };
void legacy;
