import { describe, expect, it } from 'vitest';
import {
	createStep,
	formatSummary,
	nextStepId,
	stepLabel,
	summarize,
	toDefinition,
	type FlowDocument,
	type StepTypeInfo
} from './document';

const registry: StepTypeInfo[] = [
	{ type: 'integrity-check', className: '%SYS.Task.IntegrityCheck', category: 'verification', destructive: false, pausable: false },
	{ type: 'purge-audit-records', className: '%SYS.Task.PurgeAuditDatabase', category: 'purge', destructive: true, pausable: true },
	{ type: 'switch-journal', className: '%SYS.Task.SwitchJournal', category: 'journal', destructive: false, pausable: false },
	{ type: 'custom', className: '', category: 'custom', destructive: false, pausable: false }
];
const info = (type: string) => registry.find((r) => r.type === type)!;

function canonical(): FlowDocument {
	const steps = [
		createStep(info('integrity-check'), '01', 'Default'),
		createStep(info('integrity-check'), '02', 'Default'),
		createStep(info('integrity-check'), '03', 'Default'),
		createStep(info('purge-audit-records'), '04', 'Default'),
		createStep(info('switch-journal'), '05', 'Default')
	];
	return {
		id: null,
		name: 'Heavy maintenance',
		revision: 0,
		savedAt: null,
		defaultCategory: 'Default',
		steps,
		edges: [
			{ source: '01', target: '04' },
			{ source: '02', target: '04' },
			{ source: '03', target: '04' },
			{ source: '04', target: '05' }
		],
		positions: { '01': { x: 0, y: 0 }, '04': { x: 320, y: 160 } }
	};
}

describe('stepLabel', () => {
	it('turns a registry type into a sentence-case label', () => {
		expect(stepLabel('purge-audit-records')).toBe('Purge audit records');
	});
});

describe('nextStepId', () => {
	it('starts at 01', () => {
		expect(nextStepId([])).toBe('01');
	});

	it('continues after the highest existing id, not the count', () => {
		const doc = canonical();
		expect(nextStepId(doc.steps.filter((s) => s.id !== '02'))).toBe('06');
	});
});

describe('createStep', () => {
	it('seeds the fields the backend requires, with the flow default WQM category', () => {
		const step = createStep(info('integrity-check'), '01', 'SENTAI.NIGHT');
		expect(step).toMatchObject({
			id: '01',
			type: 'integrity-check',
			taskName: 'Integrity check',
			namespace: '%SYS',
			wqmCategory: 'SENTAI.NIGHT'
		});
	});

	it('pre-fills daysToKeep for purge-audit-records, which the validator requires', () => {
		expect(createStep(info('purge-audit-records'), '04', 'Default').parameters).toEqual({ daysToKeep: 30 });
	});
});

describe('summarize (status bar, FR-009)', () => {
	it('counts steps, joins and destructive steps from the registry', () => {
		const doc = canonical();
		expect(summarize(doc.steps, doc.edges, registry)).toEqual({ steps: 5, joins: 1, destructive: 1 });
		expect(formatSummary({ steps: 5, joins: 1, destructive: 1 })).toBe('5 steps · 1 join · 1 destructive');
	});

	it('pluralizes naturally', () => {
		expect(formatSummary({ steps: 1, joins: 2, destructive: 0 })).toBe('1 step · 2 joins · 0 destructive');
	});
});

describe('toDefinition', () => {
	it('derives one ALL_MUST_SUCCEED join per fan-in target and keeps geometry separate', () => {
		const def = toDefinition(canonical());
		expect(def.joins).toEqual([{ target: '04', policy: 'ALL_MUST_SUCCEED' }]);
		expect(def.canvasGeometry).toEqual({ nodes: { '01': { x: 0, y: 0 }, '04': { x: 320, y: 160 } } });
	});

	it('never sends isDestructive — it is derived server-side from the type (FR-012)', () => {
		const def = toDefinition(canonical());
		expect(def.steps.every((s) => !('isDestructive' in s))).toBe(true);
	});

	it('omits an unset timeout rather than sending null', () => {
		const def = toDefinition(canonical());
		expect('timeoutMinutes' in def.steps[0]).toBe(false);
	});
});
