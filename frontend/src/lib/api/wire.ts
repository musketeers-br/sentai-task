// Adapters between the backend's actual JSON (see specs/003-backend-objectscript/evidence/)
// and the frontend's domain types. The response bodies deviate from openapi.yaml in small ways
// (numbers as strings, "" for absent objects, booleans as "0"/"1"); this is the only module
// that knows about that.
import type { FlowDocument, FlowStep, Position, StepCategory, StepTypeInfo } from '$lib/flow/document';

export interface WireStepType {
	type: string;
	class: string;
	category: string;
	destructive: boolean;
	pausable: boolean;
	available?: boolean;
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
		parameters: w.parameters && typeof w.parameters === 'object' ? { ...w.parameters } : {}
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

export function fromWireStepTypes(list: WireStepType[]): StepTypeInfo[] {
	return list.map((t) => ({
		type: t.type,
		className: t.class,
		category: t.category as StepCategory,
		destructive: t.destructive === true,
		pausable: t.pausable === true,
		// Fail closed: a catalog without the field is treated as "not proven executable".
		available: t.available === true
	}));
}
