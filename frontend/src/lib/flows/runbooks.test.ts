/// <reference types="node" />
import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
import type { ApiError, ApiResult } from '$lib/api/client';
import type { ParameterSpec, StepTypeInfo, FlowDocument } from '$lib/flow/document';
import type { FlowSummaryView } from './list';
import { RUNBOOKS, runbookSlug, useRunbook } from './runbooks';

// Spec 022 Phase 2 (data-model §1): the curated runbook catalog and its two-sided fixture sync.

/** The catalog's available types as GET /catalog/step-types reports them (StepType.cls, 2026-10-01). */
const registry: StepTypeInfo[] = [
	{ type: 'integrity-check', className: '%SYS.Task.IntegrityCheck', category: 'verification', destructive: false, pausable: false, available: true, executor: 'platform-api', parameters: [] },
	{ type: 'switch-journal', className: '%SYS.Task.SwitchJournal', category: 'journal', destructive: false, pausable: false, available: true, executor: 'in-process', parameters: [] },
	{ type: 'purge-task-history', className: '%SYS.Task.PurgeTaskHistory', category: 'purge', destructive: true, pausable: false, available: true, executor: 'in-process', parameters: [{ name: 'keepDays', type: 'integer', required: false, default: 30, min: 0, description: 'Days of task history to keep' }] },
	{ type: 'storage-headroom-check', className: 'sentai.steps.StorageHeadroomCheck', category: 'storage', destructive: false, pausable: false, available: true, executor: 'in-process', parameters: [{ name: 'minFreePercent', type: 'number', required: false, default: 10, min: 0, max: 100, description: 'Fail when any database or journal location has less free space than this percentage' }] },
	{ type: 'db-size-report', className: 'sentai.steps.DatabaseSizeReport', category: 'verification', destructive: false, pausable: false, available: true, executor: 'in-process', parameters: [] },
	{ type: 'security-posture-report', className: 'sentai.steps.reports.SecurityPosture', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read', parameters: [{ name: 'failOnFindings', type: 'boolean', required: false, default: false, description: 'Fail the step when any high finding exists' }] },
	{ type: 'web-app-inventory', className: 'sentai.steps.reports.WebAppInventory', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read', parameters: [{ name: 'failOnFindings', type: 'boolean', required: false, default: false, description: 'Fail the step when any high finding exists' }] },
	{ type: 'secrets-inventory', className: 'sentai.steps.reports.SecretsInventory', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read', parameters: [] },
	{ type: 'certificate-expiry-check', className: 'sentai.steps.reports.CertificateExpiry', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read', parameters: [{ name: 'warnDays', type: 'integer', required: false, default: 30, min: 1, max: 365, description: 'Fail when a certificate expires within this many days (or has expired)' }] },
	{ type: 'permissions-inventory', className: 'sentai.steps.reports.PermissionsInventory', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read', parameters: [{ name: 'failOnFindings', type: 'boolean', required: false, default: false, description: 'Fail the step when any high finding exists' }] },
	{ type: 'oauth-inventory', className: 'sentai.steps.reports.OAuthInventory', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read', parameters: [{ name: 'failOnFindings', type: 'boolean', required: false, default: false, description: 'Fail the step when any high finding exists' }] }
];

const fixture = (file: string): Record<string, unknown> =>
	JSON.parse(readFileSync(new URL('../../../../tests/fixtures/' + file, import.meta.url), 'utf8'));

describe('RUNBOOKS (FR-002, FR-011, data-model §1)', () => {
	it('is exactly the seven launch cards: the six the spec names plus the example', () => {
		expect(RUNBOOKS.map((r) => r.title)).toEqual([
			'Nightly integrity sweep',
			'Weekly maintenance window',
			'Pre-upgrade checklist',
			'Certificate expiry watch',
			'Security review',
			'Cross-server nightly',
			'Example: storage health check'
		]);
	});

	it('has unique, non-empty flowNames and each definition is named by its flowName', () => {
		const names = RUNBOOKS.map((r) => r.flowName);
		expect(new Set(names.map((n) => n.toLowerCase())).size).toBe(names.length);
		for (const runbook of RUNBOOKS) {
			expect(runbook.flowName).not.toBe('');
			expect(runbook.definition.name).toBe(runbook.flowName);
		}
	});

	it('the cross-server card opens the seeded showcase, so its flowName is the showcase name', () => {
		const cross = RUNBOOKS.find((r) => r.title === 'Cross-server nightly')!;
		expect(cross.flowName).toBe('Showcase: nightly checks across servers');
	});

	it('uses only step types the catalog declares and marks available (FR-011)', () => {
		for (const runbook of RUNBOOKS) {
			for (const s of runbook.definition.steps) {
				const info = registry.find((r) => r.type === s.type);
				expect(info, `${runbook.flowName}: ${s.type}`).toBeDefined();
				expect(info!.available, `${runbook.flowName}: ${s.type}`).toBe(true);
			}
		}
	});

	it('fills every declared parameter (FR-011, the example.test.ts rule generalized)', () => {
		for (const runbook of RUNBOOKS) {
			for (const s of runbook.definition.steps) {
				const declared = registry.find((r) => r.type === s.type)?.parameters ?? [];
				for (const p of declared as ParameterSpec[]) {
					const value = s.parameters?.[p.name];
					expect(value, `${runbook.flowName}: ${s.type}.${p.name}`).toBeDefined();
					if (p.min !== undefined) expect(value as number).toBeGreaterThanOrEqual(p.min);
					if (p.max !== undefined) expect(value as number).toBeLessThanOrEqual(p.max);
				}
			}
		}
	});

	it('ships geometry for every step of every runbook (the mini-graph is drawn from it, FR-003)', () => {
		for (const runbook of RUNBOOKS) {
			const ids = runbook.definition.steps.map((s) => s.id).sort();
			expect(Object.keys(runbook.definition.canvasGeometry.nodes).sort(), runbook.flowName).toEqual(ids);
		}
	});

	it('carries a one-line purpose for every card; a cadence only where one is suggested (FR-003, FR-004)', () => {
		const cadence: Record<string, string | undefined> = {
			'Nightly integrity sweep': 'nightly',
			'Weekly maintenance window': 'weekly',
			'Pre-upgrade checklist': undefined,
			'Certificate expiry watch': 'daily',
			'Security review': undefined,
			'Cross-server nightly': 'nightly',
			'Example: storage health check': undefined
		};
		for (const runbook of RUNBOOKS) {
			expect(runbook.purpose).not.toBe('');
			expect(runbook.suggestedCadence).toBe(cadence[runbook.title]);
		}
	});

	it('joins only target steps that exist and are the head of at least one edge', () => {
		for (const runbook of RUNBOOKS) {
			const ids = new Set(runbook.definition.steps.map((s) => s.id));
			for (const join of runbook.definition.joins) {
				expect(ids.has(join.target), `${runbook.flowName}: join ${join.target}`).toBe(true);
				expect(
					runbook.definition.edges.some((e) => e.target === join.target),
					`${runbook.flowName}: join ${join.target} has incoming edges`
				).toBe(true);
			}
		}
	});
});

describe('the three shared definitions equal the fixtures (research R-2, data-model §7)', () => {
	it('the weekly window equals weekly-window-flow.json (schemaVersion is sentai-demo wire data, not part of a definition)', () => {
		const weekly = fixture('weekly-window-flow.json');
		delete weekly.schemaVersion;
		const runbook = RUNBOOKS.find((r) => r.title === 'Weekly maintenance window')!;
		expect(runbook.definition).toEqual(weekly);
	});

	it('the cross-server card equals showcase-flow.json', () => {
		const runbook = RUNBOOKS.find((r) => r.title === 'Cross-server nightly')!;
		expect(runbook.definition).toEqual(fixture('showcase-flow.json'));
	});

	it('the example card equals example-flow.json (spec 010 R-6 keeps this comparison)', () => {
		const runbook = RUNBOOKS.find((r) => r.title === 'Example: storage health check')!;
		expect(runbook.definition).toEqual(fixture('example-flow.json'));
	});
});

describe('runbookSlug (contracts/runbook-gallery.md)', () => {
	it('derives the card id from the flow name: lower-cased, non-alphanumerics collapsed', () => {
		expect(runbookSlug('Showcase: nightly checks across servers')).toBe('showcase-nightly-checks-across-servers');
		expect(runbookSlug('Example: storage health check')).toBe('example-storage-health-check');
		expect(runbookSlug('Security review')).toBe('security-review');
	});
});

describe('useRunbook (FR-006, FR-009; spec 010 FR-017 generalized, data-model §4)', () => {
	const byTitle = (title: string) => RUNBOOKS.find((r) => r.title === title)!;
	const row = (id: string, name: string): FlowSummaryView => ({ id, name, revision: 1, savedAt: null });
	const ok = <T>(value: T): ApiResult<T> => ({ ok: true, value });
	const refused = (status: number, detail: string): ApiResult<never> => ({
		ok: false,
		error: { kind: 'problem', status, title: status === 409 ? 'Conflict' : 'Forbidden', detail }
	});
	const created = (id: string, name: string): FlowDocument => ({
		id,
		name,
		revision: 1,
		savedAt: null,
		defaultCategory: 'Default',
		steps: [],
		edges: [],
		positions: {}
	});

	it('opens the existing flow of that name without creating one', async () => {
		const api = { listFlows: vi.fn(async () => ok([row('3', 'x'), row('9', 'weekly maintenance window')])), createFlow: vi.fn() };
		expect(await useRunbook(api, byTitle('Weekly maintenance window'))).toEqual({ ok: true, value: '9' });
		expect(api.createFlow).not.toHaveBeenCalled();
	});

	it('creates it once when none exists, sending the definition exactly (FR-006, FR-011)', async () => {
		const watch = byTitle('Certificate expiry watch');
		const api = {
			listFlows: vi.fn(async () => ok([row('3', 'x')])),
			createFlow: vi.fn(async (def) => ok(created('12', def.name)))
		};
		expect(await useRunbook(api, watch)).toEqual({ ok: true, value: '12' });
		expect(api.createFlow).toHaveBeenCalledTimes(1);
		expect(api.createFlow.mock.calls[0][0]).toEqual(watch.definition);
	});

	it('a name clash means someone created it meanwhile: list again and open that one', async () => {
		const listFlows = vi
			.fn()
			.mockResolvedValueOnce(ok([]))
			.mockResolvedValueOnce(ok([row('15', 'Security review')]));
		const api = { listFlows, createFlow: vi.fn(async () => refused(409, 'A flow with this name already exists')) };
		expect(await useRunbook(api, byTitle('Security review'))).toEqual({ ok: true, value: '15' });
		expect(listFlows).toHaveBeenCalledTimes(2);
		expect(api.createFlow).toHaveBeenCalledTimes(1);
	});

	it('a clash with no such flow to open returns the platform refusal as-is', async () => {
		const api = { listFlows: vi.fn(async () => ok([])), createFlow: vi.fn(async () => refused(409, 'A flow with this name already exists')) };
		expect(await useRunbook(api, byTitle('Nightly integrity sweep'))).toEqual(
			refused(409, 'A flow with this name already exists')
		);
	});

	it('a refused list is returned as-is and nothing is created', async () => {
		const error: ApiError = { kind: 'problem', status: 403, title: 'Forbidden', detail: 'not permitted' };
		const api = { listFlows: vi.fn(async () => ({ ok: false as const, error })), createFlow: vi.fn() };
		expect(await useRunbook(api, byTitle('Pre-upgrade checklist'))).toEqual({ ok: false, error });
		expect(api.createFlow).not.toHaveBeenCalled();
	});

	it('a refused create is returned as-is, verbatim, never retried (FR-009)', async () => {
		const api = {
			listFlows: vi.fn(async () => ok([])),
			createFlow: vi.fn(async () => refused(403, 'the platform said no'))
		};
		expect(await useRunbook(api, byTitle('Security review'))).toEqual(refused(403, 'the platform said no'));
		expect(api.createFlow).toHaveBeenCalledTimes(1);
		expect(api.listFlows).toHaveBeenCalledTimes(1);
	});
});
