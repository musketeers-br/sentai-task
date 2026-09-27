import { joinTargets, type EdgeRef } from './graph';

export type StepCategory = 'verification' | 'storage' | 'journal' | 'purge' | 'backup' | 'custom';

/** One entry of the backend's closed step-type registry (GET /catalog/step-types). */
export interface StepTypeInfo {
	type: string;
	className: string;
	category: StepCategory;
	destructive: boolean;
	pausable: boolean;
	/** Spec 004 D-1: whether the target platform can execute this type in this release. */
	available: boolean;
	/** Spec 008 FR-008: whether a step of this type may run on a target server. */
	remoteCapable?: boolean;
	/** Spec 005: the API's name for the type (absent in a pre-005 catalog). */
	label?: string;
	/** Spec 005: how it executes; `in-process` types form the palette's *Custom* group. */
	executor?: 'platform-api' | 'in-process';
	/** Spec 005: the declared parameter schema; `[]` = takes no parameters; absent = none declared. */
	parameters?: ParameterSpec[];
}

/** One declared parameter (spec 005 catalog); the backend-only `property` is not carried. */
export interface ParameterSpec {
	name: string;
	type: 'string' | 'integer' | 'number' | 'boolean';
	required: boolean;
	default?: unknown;
	min?: number;
	max?: number;
	description: string;
}

export interface FlowStep {
	id: string;
	type: string;
	taskName: string;
	namespace: string;
	databaseDirectory: string;
	runAsUser: string;
	timeoutMinutes: number | null;
	wqmCategory: string;
	customClass: string;
	parameters: Record<string, unknown>;
	/** Spec 008: the target server the step runs on; absent = this instance. */
	target?: string;
}

export interface Position {
	x: number;
	y: number;
}

export interface FlowDocument {
	id: string | null;
	name: string;
	revision: number;
	savedAt: string | null;
	defaultCategory: string;
	steps: FlowStep[];
	edges: EdgeRef[];
	positions: Record<string, Position>;
}

/** Wire shape of FlowDefinition in contracts/openapi.yaml (the request body of POST/PUT). */
export interface FlowDefinition {
	name: string;
	defaultCategory: string;
	steps: Array<Partial<FlowStep> & Pick<FlowStep, 'id' | 'type' | 'taskName' | 'namespace'>>;
	edges: EdgeRef[];
	joins: Array<{ target: string; policy: 'ALL_MUST_SUCCEED' }>;
	canvasGeometry: { nodes: Record<string, Position> };
}

export interface FlowSummary {
	steps: number;
	joins: number;
	destructive: number;
}

// Presentation defaults only — the registry stays the sole authority on what a step can be.
const DEFAULT_PARAMETERS: Record<string, Record<string, unknown>> = {
	'purge-audit-records': { daysToKeep: 30 }
};

export function stepLabel(type: string): string {
	if (type === 'custom') return 'Custom step';
	const words = type.split('-').join(' ');
	return words.charAt(0).toUpperCase() + words.slice(1);
}

/** The name shown for a type: the API's label, else one derived from the type id (pre-005). */
export function typeLabel(info: Pick<StepTypeInfo, 'type' | 'label'>): string {
	return info.label ?? stepLabel(info.type);
}

export interface PaletteGroup {
	id: StepCategory;
	types: StepTypeInfo[];
}

const GROUP_ORDER: StepCategory[] = ['verification', 'storage', 'journal', 'purge', 'backup', 'custom'];

/**
 * Palette groups (spec 007 D-6, Clarifications Q1): every in-process type and the legacy `custom`
 * entry under *Custom*; the others by category, in the spec 002 order. Display only — which types
 * exist and whether they can be placed is the API's.
 */
export function paletteGroups(registry: StepTypeInfo[]): PaletteGroup[] {
	const groupOf = (t: StepTypeInfo): StepCategory => (t.executor === 'in-process' || t.type === 'custom' ? 'custom' : t.category);
	return GROUP_ORDER.map((id) => ({ id, types: registry.filter((t) => groupOf(t) === id) })).filter((g) => g.types.length > 0);
}

export function nextStepId(steps: Pick<FlowStep, 'id'>[]): string {
	const highest = steps.reduce((max, s) => Math.max(max, Number.parseInt(s.id, 10) || 0), 0);
	return String(highest + 1).padStart(2, '0');
}

export function createStep(info: StepTypeInfo, id: string, defaultCategory: string): FlowStep {
	return {
		id,
		type: info.type,
		taskName: typeLabel(info),
		namespace: '%SYS',
		databaseDirectory: '',
		runAsUser: '',
		timeoutMinutes: null,
		wqmCategory: defaultCategory,
		customClass: '',
		// R-7: a declared schema's defaults are the backend's to apply; only a pre-005 catalog (no
		// schema) keeps the old presentation default.
		parameters: info.parameters !== undefined ? {} : { ...(DEFAULT_PARAMETERS[info.type] ?? {}) }
	};
}

export function summarize(steps: FlowStep[], edges: EdgeRef[], registry: StepTypeInfo[]): FlowSummary {
	const destructiveTypes = new Set(registry.filter((r) => r.destructive).map((r) => r.type));
	return {
		steps: steps.length,
		joins: joinTargets(edges).length,
		destructive: steps.filter((s) => destructiveTypes.has(s.type)).length
	};
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;

export function formatSummary(s: FlowSummary): string {
	return `${plural(s.steps, 'step')} · ${plural(s.joins, 'join')} · ${s.destructive} destructive`;
}

export function toDefinition(doc: FlowDocument): FlowDefinition {
	return {
		name: doc.name,
		defaultCategory: doc.defaultCategory,
		steps: doc.steps.map(({ timeoutMinutes, ...rest }) =>
			timeoutMinutes === null ? rest : { ...rest, timeoutMinutes }
		),
		edges: doc.edges.map(({ source, target }) => ({ source, target })),
		joins: joinTargets(doc.edges).map((target) => ({ target, policy: 'ALL_MUST_SUCCEED' as const })),
		canvasGeometry: { nodes: doc.positions }
	};
}

export interface ConfirmationPrompt {
	stepId: string;
	taskName: string;
	/** What the operator is asked to type: the step's database directory, else its namespace. */
	expected: string;
}

/**
 * The typed confirmation of every destructive step (spec 002 FR-013, spec 007 D-7): one prompt
 * per step the registry marks destructive, and the values typed so far as the dispatch body's
 * `confirmations`. Whether a value matches is the backend's decision (HTTP 428), never checked here.
 */
export function confirmationsFor(
	steps: FlowStep[],
	registry: StepTypeInfo[],
	typed: Record<string, string>
): { prompts: ConfirmationPrompt[]; confirmations: Array<{ stepId: string; typedName: string }>; complete: boolean } {
	const destructiveTypes = new Set(registry.filter((r) => r.destructive).map((r) => r.type));
	const destructive = steps.filter((s) => destructiveTypes.has(s.type));
	const confirmations = destructive.map((s) => ({ stepId: s.id, typedName: typed[s.id] ?? '' }));
	return {
		prompts: destructive.map((s) => ({ stepId: s.id, taskName: s.taskName, expected: s.databaseDirectory || s.namespace })),
		confirmations,
		complete: confirmations.every((c) => c.typedName !== '')
	};
}
