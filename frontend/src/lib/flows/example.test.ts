/// <reference types="node" />
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import type { StepTypeInfo } from '$lib/flow/document';
import { EXAMPLE_FLOW_NAME, EXAMPLE_STEP_TYPES, exampleAvailable, exampleDefinition } from './example';

// spec 010 US4 (research R-4, data-model §4): the ready-made example flow's definition. Since
// spec 022 it is the seventh gallery card; its create-or-open is useRunbook (runbooks.test.ts).

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

describe('exampleDefinition matches the shared fixture (spec 011 R-6)', () => {
	// The demo seed (sentai.demo.Demo, ObjectScript) creates the same flow from its own copy; both
	// are compared with tests/fixtures/example-flow.json, so neither can drift alone.
	it('equals tests/fixtures/example-flow.json', () => {
		const fixture = JSON.parse(readFileSync(new URL('../../../../tests/fixtures/example-flow.json', import.meta.url), 'utf8'));
		expect(exampleDefinition()).toEqual(fixture);
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
