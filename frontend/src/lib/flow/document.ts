import { joinTargets, type EdgeRef } from './graph';

export type StepCategory = 'verification' | 'storage' | 'journal' | 'purge' | 'backup' | 'custom';

/** One entry of the backend's closed step-type registry (GET /catalog/step-types). */
export interface StepTypeInfo {
	type: string;
	className: string;
	category: StepCategory;
	destructive: boolean;
	pausable: boolean;
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

export function nextStepId(steps: Pick<FlowStep, 'id'>[]): string {
	const highest = steps.reduce((max, s) => Math.max(max, Number.parseInt(s.id, 10) || 0), 0);
	return String(highest + 1).padStart(2, '0');
}

export function createStep(info: StepTypeInfo, id: string, defaultCategory: string): FlowStep {
	return {
		id,
		type: info.type,
		taskName: stepLabel(info.type),
		namespace: '%SYS',
		databaseDirectory: '',
		runAsUser: '',
		timeoutMinutes: null,
		wqmCategory: defaultCategory,
		customClass: '',
		parameters: { ...(DEFAULT_PARAMETERS[info.type] ?? {}) }
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
