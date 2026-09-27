import { describe, expect, it, vi } from 'vitest';
import type { ApiError, ApiResult } from '$lib/api/client';
import type { FlowDefinition, FlowDocument, StepTypeInfo } from '$lib/flow/document';
import { EXAMPLE_FLOW_NAME, EXAMPLE_STEP_TYPES, exampleAvailable, exampleDefinition, findExample, openExample } from './example';
import type { FlowSummaryView } from './list';

// spec 010 US4 (research R-4, data-model §4): the ready-made example flow.

/** The two types as GET /catalog/step-types reported them on 2026-09-27 (research R-4.1). */
const registry: StepTypeInfo[] = [
	{
		type: 'storage-headroom-check',
		className: 'sentai.steps.StorageHeadroomCheck',
		category: 'storage',
		destructive: false,
		pausable: false,
		available: true,
		executor: 'in-process',
		parameters: [
			{ name: 'minFreePercent', type: 'number', required: false, default: 10, min: 0, max: 100, description: 'Fail when any database or journal location has less free space than this percentage' }
		]
	},
	{
		type: 'db-size-report',
		className: 'sentai.steps.DatabaseSizeReport',
		category: 'storage',
		destructive: false,
		pausable: false,
		available: true,
		executor: 'in-process',
		parameters: []
	}
];

describe('exampleDefinition (FR-015)', () => {
	const def = exampleDefinition();

	it('is the named, two-step, all-parallel flow of declared read-only types', () => {
		expect(def.name).toBe('Example: storage health check');
		expect(def.name).toBe(EXAMPLE_FLOW_NAME);
		expect(def.steps.map((s) => s.type)).toEqual([...EXAMPLE_STEP_TYPES]);
		expect(def.steps.length).toBeGreaterThanOrEqual(2);
		expect(def.edges).toEqual([]); // every step in wave 1
		expect(def.joins).toEqual([]);
		expect(def.defaultCategory).toBe('Default');
		expect(def.steps.map((s) => s.taskName)).toEqual(['Storage headroom check', 'Database size report']);
		for (const step of def.steps) {
			expect(step.namespace).toBe('%SYS');
			expect(step.wqmCategory).toBe('Default');
		}
		expect(Object.keys(def.canvasGeometry.nodes)).toEqual(['01', '02']);
	});

	it('fills every declared parameter with a value within its bounds', () => {
		expect(def.steps[0].parameters).toEqual({ minFreePercent: 10 });
		expect(def.steps[1].parameters).toEqual({});
		for (const step of def.steps) {
			const declared = registry.find((r) => r.type === step.type)!.parameters ?? [];
			for (const p of declared) {
				const value = step.parameters?.[p.name];
				expect(value, `${step.type}.${p.name}`).toBeTypeOf('number');
				if (p.min !== undefined) expect(value as number).toBeGreaterThanOrEqual(p.min);
				if (p.max !== undefined) expect(value as number).toBeLessThanOrEqual(p.max);
			}
		}
	});
});

describe('exampleAvailable (FR-019)', () => {
	it('is offered only when every type is present, available and non-destructive', () => {
		expect(exampleAvailable(registry)).toBe(true);
		expect(exampleAvailable(registry.slice(0, 1))).toBe(false);
		expect(exampleAvailable([registry[0], { ...registry[1], available: false }])).toBe(false);
		expect(exampleAvailable([registry[0], { ...registry[1], destructive: true }])).toBe(false);
		expect(exampleAvailable([])).toBe(false);
	});
});

describe('findExample (FR-017)', () => {
	const row = (id: string, name: string): FlowSummaryView => ({ id, name, revision: 1, savedAt: null });

	it('matches the example by name, ignoring case like the platform\'s unique index', () => {
		expect(findExample([row('1', 'other'), row('7', 'example: STORAGE health check')])?.id).toBe('7');
		expect(findExample([row('1', 'Example: storage health check (copy)')])).toBeNull();
		expect(findExample([])).toBeNull();
	});
});

describe('openExample (FR-017: open the existing one, else create it; never a duplicate)', () => {
	const row = (id: string, name: string): FlowSummaryView => ({ id, name, revision: 1, savedAt: null });
	const ok = <T>(value: T): ApiResult<T> => ({ ok: true, value });
	const refused = (status: number, detail: string): ApiResult<never> => ({
		ok: false,
		error: { kind: 'problem', status, title: status === 409 ? 'Conflict' : 'Forbidden', detail }
	});
	const created = (id: string, def: FlowDefinition): FlowDocument => ({
		id,
		name: def.name,
		revision: 1,
		savedAt: null,
		defaultCategory: def.defaultCategory,
		steps: [],
		edges: [],
		positions: {}
	});

	it('opens the existing example without creating one', async () => {
		const api = { listFlows: vi.fn(async () => ok([row('3', 'x'), row('9', EXAMPLE_FLOW_NAME)])), createFlow: vi.fn() };
		expect(await openExample(api)).toEqual({ ok: true, value: '9' });
		expect(api.createFlow).not.toHaveBeenCalled();
	});

	it('creates it once when it does not exist', async () => {
		const api = {
			listFlows: vi.fn(async () => ok([row('3', 'x')])),
			createFlow: vi.fn(async (def: FlowDefinition) => ok(created('12', def)))
		};
		expect(await openExample(api)).toEqual({ ok: true, value: '12' });
		expect(api.createFlow).toHaveBeenCalledTimes(1);
		expect(api.createFlow.mock.calls[0][0]).toEqual(exampleDefinition());
	});

	it('a name clash means someone created it meanwhile: list again and open that one', async () => {
		const listFlows = vi
			.fn()
			.mockResolvedValueOnce(ok([]))
			.mockResolvedValueOnce(ok([row('15', EXAMPLE_FLOW_NAME)]));
		const api = { listFlows, createFlow: vi.fn(async () => refused(409, 'A flow with this name already exists')) };
		expect(await openExample(api)).toEqual({ ok: true, value: '15' });
		expect(listFlows).toHaveBeenCalledTimes(2);
		expect(api.createFlow).toHaveBeenCalledTimes(1);
	});

	it('a clash with no example to open returns the platform\'s refusal as-is', async () => {
		const api = { listFlows: vi.fn(async () => ok([])), createFlow: vi.fn(async () => refused(409, 'A flow with this name already exists')) };
		const result = await openExample(api);
		expect(result).toEqual(refused(409, 'A flow with this name already exists'));
	});

	it('a refused list is returned as-is and nothing is created', async () => {
		const error: ApiError = { kind: 'problem', status: 403, title: 'Forbidden', detail: 'not permitted' };
		const api = { listFlows: vi.fn(async () => ({ ok: false as const, error })), createFlow: vi.fn() };
		expect(await openExample(api)).toEqual({ ok: false, error });
		expect(api.createFlow).not.toHaveBeenCalled();
	});
});
