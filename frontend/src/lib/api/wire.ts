// Adapters between the backend's actual JSON (see specs/003-backend-objectscript/evidence/)
// and the frontend's domain types. The response bodies deviate from openapi.yaml in small ways
// (numbers as strings, "" for absent objects, booleans as "0"/"1"); this is the only module
// that knows about that.
import type { FlowDocument, FlowStep, ParameterSpec, Position, StepCategory, StepTypeInfo } from '$lib/flow/document';
import type { FlowSummaryView } from '$lib/flows/list';
// R-011: `StepTypeInfo` gains no `description`. The catalog response carries one, and this module
// deliberately does not model it — the palette does not display it in this feature.
import type { StepSearchOutcome, UnavailableReason } from '$lib/palette/search';

export interface WireStepType {
	type: string;
	class: string;
	category: string;
	destructive: boolean;
	pausable: boolean;
	available?: boolean;
	remoteCapable?: boolean;
	label?: string;
	executor?: string;
	parameters?: Array<{ name: string; property?: string; type: string; required?: boolean; default?: unknown; min?: number; max?: number; description?: string }>;
}

export interface WireStep {
	id: string;
	type: string;
	taskName: string;
	namespace: string;
	databaseDirectory?: string;
	runAsUser?: string;
	timeoutMinutes?: number | string | null;
	wqmCategory?: string;
	customClass?: string;
	parameters?: Record<string, unknown>;
	isDestructive?: unknown;
	target?: string;
}

export interface WireFlow {
	id: string;
	name: string;
	revision: number | string;
	savedAt?: string | null;
	savedBy?: string;
	defaultCategory?: string;
	steps: WireStep[];
	edges: Array<{ source: string; target: string }>;
	joins?: unknown[];
	canvasGeometry?: '' | { nodes?: Record<string, Position> } | null;
}

export interface WireFlowSummary {
	id: string;
	name: string;
	revision: number | string;
	savedAt?: string | null;
	savedBy?: string;
	nextRun?: string | null;
}

function toNumberOrNull(value: unknown): number | null {
	if (value === null || value === undefined || value === '') return null;
	const n = Number(value);
	return Number.isFinite(n) ? n : null;
}

export function fromWireStep(w: WireStep): FlowStep {
	return {
		id: w.id,
		type: w.type,
		taskName: w.taskName ?? '',
		namespace: w.namespace ?? '',
		databaseDirectory: w.databaseDirectory ?? '',
		runAsUser: w.runAsUser ?? '',
		// An omitted timeout is persisted as 0; a zero-minute timeout is not a real setting.
		timeoutMinutes: toNumberOrNull(w.timeoutMinutes) || null,
		wqmCategory: w.wqmCategory ?? '',
		customClass: w.customClass ?? '',
		parameters: w.parameters && typeof w.parameters === 'object' ? { ...w.parameters } : {},
		// Spec 008: only a remote step carries `target`; a local one reads exactly as before.
		...(w.target ? { target: w.target } : {})
	};
}

/** Spec 010 FR-002: one row of GET /flows; `savedAt` stays in the platform's own format. */
export function fromWireFlowSummary(w: WireFlowSummary): FlowSummaryView {
	return {
		id: String(w.id),
		name: w.name,
		revision: toNumberOrNull(w.revision) ?? 0,
		savedAt: w.savedAt || null
	};
}

export function fromWireFlow(w: WireFlow): FlowDocument {
	const geometry = w.canvasGeometry && typeof w.canvasGeometry === 'object' ? w.canvasGeometry : {};
	return {
		id: String(w.id),
		name: w.name,
		revision: toNumberOrNull(w.revision) ?? 0,
		savedAt: w.savedAt || null,
		defaultCategory: w.defaultCategory || 'Default',
		steps: w.steps.map(fromWireStep).sort((a, b) => a.id.localeCompare(b.id)),
		edges: w.edges.map(({ source, target }) => ({ source, target })),
		positions: { ...(geometry.nodes ?? {}) }
	};
}

export function fromWireStepTypes(list: WireStepType[]): StepTypeInfo[] {	return list.map((t) => ({
		type: t.type,
		className: t.class,
		category: t.category as StepCategory,
		destructive: t.destructive === true,
		pausable: t.pausable === true,
		// Fail closed: a catalog without the field is treated as "not proven executable".
		available: t.available === true,
		// Spec 008: present only when the API says so; absent reads as "not remote-capable".
		...(t.remoteCapable === true ? { remoteCapable: true } : {}),
		// Spec 005 (spec 007 T007): absent in a pre-005 catalog, so a pre-005 entry maps as before.
		...(t.label ? { label: t.label } : {}),
		...(t.executor === 'in-process' || t.executor === 'platform-api' || t.executor === 'platform-read'
			? { executor: t.executor }
			: {}),
		...(Array.isArray(t.parameters)
			? {
					parameters: t.parameters.map((p) => ({
						name: p.name,
						type: p.type as ParameterSpec['type'],
						required: p.required === true,
						...(p.default !== undefined ? { default: p.default } : {}),
						...(p.min !== undefined ? { min: p.min } : {}),
						...(p.max !== undefined ? { max: p.max } : {}),
						description: p.description ?? ''
					}))
				}
			: {})
	}));
}

/**
 * Spec 011: the search answer, validated on the way in.
 *
 * Both answers are `200`, so a body that is neither shape is a defect rather than a degraded
 * provider — it still degrades the palette rather than throwing into the component, because a
 * malformed server answer must never be able to become an error state on screen (Constitution IV,
 * FR-023). An unrecognised `reason` becomes `error` for the same reason: it is still a reason, and
 * the reason is never rendered anyway.
 */
export function fromWireStepSearch(body: unknown): StepSearchOutcome {
	const degraded: StepSearchOutcome = { available: false, reason: 'error' };
	if (typeof body !== 'object' || body === null) return degraded;
	const record = body as Record<string, unknown>;
	if (record.available === true) {
		if (!Array.isArray(record.matches)) return degraded;
		const matches: { type: string; score: number }[] = [];
		for (const item of record.matches) {
			if (typeof item !== 'object' || item === null) return degraded;
			const { type, score } = item as Record<string, unknown>;
			// A match without a type names nothing the palette could render, and a score that is not
			// a number is not a score: the entry is dropped rather than offered as a ranked result.
			if (typeof type !== 'string' || type === '') continue;
			const n = Number(score);
			if (!Number.isFinite(n)) continue;
			matches.push({ type, score: n });
		}
		return { available: true, matches };
	}
	const reason = record.reason;
	return {
		available: false,
		reason: REASONS.has(reason as UnavailableReason) ? (reason as UnavailableReason) : 'error'
	};
}

const REASONS = new Set<UnavailableReason>([
	'not-configured',
	'unreachable',
	'slow',
	'incompatible',
	'warming',
	'error'
]);
