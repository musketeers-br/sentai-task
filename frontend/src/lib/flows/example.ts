// Spec 010 US4 (research R-4, data-model §4): the ready-made example flow. Data, not code
// (Constitution II): only declared registry types, created through the ordinary POST /flows with
// the operator's own sign-in and validated by the backend like any flow. Its name is its identity:
// the platform's unique (case-insensitive) name index makes a duplicate impossible (FR-017).
import type { ApiResult } from '$lib/api/client';
import type { FlowDefinition, FlowDocument, StepTypeInfo } from '$lib/flow/document';
import type { FlowSummaryView } from './list';

export const EXAMPLE_FLOW_NAME = 'Example: storage health check';
/** Both in-process and read-only; probed to validate with 0 errors and complete in ~1 s. */
export const EXAMPLE_STEP_TYPES = ['storage-headroom-check', 'db-size-report'] as const;

/** Two steps, no edges — both run in the first wave, in parallel. */
export function exampleDefinition(): FlowDefinition {
	const step = (id: string, type: string, taskName: string, parameters: Record<string, unknown>) => ({
		id,
		type,
		taskName,
		namespace: '%SYS',
		wqmCategory: 'Default',
		parameters
	});
	return {
		name: EXAMPLE_FLOW_NAME,
		defaultCategory: 'Default',
		steps: [
			// FR-015: the declared parameter is filled in (its registry default), not left implicit.
			step('01', 'storage-headroom-check', 'Storage headroom check', { minFreePercent: 10 }),
			step('02', 'db-size-report', 'Database size report', {})
		],
		edges: [],
		joins: [],
		// Side by side, clear of the canvas's top-left edge legend.
		canvasGeometry: { nodes: { '01': { x: 40, y: 160 }, '02': { x: 360, y: 160 } } }
	};
}

/** FR-019: offered only if every step type is declared, available and not destructive. */
export function exampleAvailable(registry: readonly StepTypeInfo[]): boolean {
	return EXAMPLE_STEP_TYPES.every((type) => {
		const info = registry.find((r) => r.type === type);
		return info !== undefined && info.available && !info.destructive;
	});
}

export function findExample(flows: readonly FlowSummaryView[]): FlowSummaryView | null {
	const wanted = EXAMPLE_FLOW_NAME.toLowerCase();
	return flows.find((f) => f.name.toLowerCase() === wanted) ?? null;
}

interface ExampleApi {
	listFlows(): Promise<ApiResult<FlowSummaryView[]>>;
	createFlow(def: FlowDefinition): Promise<ApiResult<FlowDocument>>;
}

/**
 * FR-017: the id of the example to open — the existing one, or a new one. A 409 on create means
 * it appeared meanwhile (another tab or operator), so the list is read again. Every refusal is
 * returned as the platform gave it.
 */
export async function openExample(api: ExampleApi): Promise<ApiResult<string>> {
	const listed = await api.listFlows();
	if (!listed.ok) return listed;
	const existing = findExample(listed.value);
	if (existing) return { ok: true, value: existing.id };

	const created = await api.createFlow(exampleDefinition());
	if (created.ok) return { ok: true, value: created.value.id! };
	if (created.error.kind === 'problem' && created.error.status === 409) {
		const again = await api.listFlows();
		const match = again.ok ? findExample(again.value) : null;
		if (match) return { ok: true, value: match.id };
	}
	return created;
}
