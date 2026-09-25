// Run state as GET /runs/{guid} reports it, adapted for the live-run screen (UI-002).
import type { EdgeRef } from '$lib/flow/graph';
import { joinTargets, incomingSources } from '$lib/flow/graph';

export type StepState = 'queued' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
export type RunState = 'running' | 'completed' | 'failed' | 'cancelled';

export const STEP_STATES: StepState[] = ['queued', 'running', 'paused', 'completed', 'failed', 'cancelled'];

export interface StepRunView {
	guid: string;
	stepId: string;
	state: StepState;
	timeQueued: string | null;
	timeStarted: string | null;
	timeFinished: string | null;
	/** Verbatim from IRIS (FR-026) — never rewritten here. */
	failureReason: string | null;
	progressCurrent: number | null;
	progressTotal: number | null;
}

export interface LogEntry {
	at: string;
	stepId: string | null;
	severity: string;
	message: string;
}

export interface RunView {
	guid: string;
	flowId: string;
	flowRevision: number;
	state: RunState;
	startedAt: string | null;
	finishedAt: string | null;
	dispatchedBy: string;
	/** Latest StepRun per step (a re-run adds a new one), ordered by step id. */
	steps: StepRunView[];
	log: LogEntry[];
}

type Wire = Record<string, unknown>;

const text = (v: unknown): string | null => (v === null || v === undefined || v === '' ? null : String(v));
const num = (v: unknown): number | null => {
	if (v === null || v === undefined || v === '') return null;
	const n = Number(v);
	return Number.isFinite(n) ? n : null;
};

/** Backend timestamps are "YYYY-MM-DD HH:MM:SS" in UTC (checked against the Date header). */
export function parseServerTime(value: string | null | undefined): number | null {
	if (!value) return null;
	const ms = Date.parse(`${value.replace(' ', 'T')}Z`);
	return Number.isNaN(ms) ? null : ms;
}

export function fromWireRun(w: Wire): RunView {
	const all = ((w.steps as Wire[]) ?? []).map(
		(s): StepRunView => ({
			guid: String(s.guid),
			stepId: String(s.stepId),
			state: String(s.state) as StepState,
			timeQueued: text(s.timeQueued),
			timeStarted: text(s.timeStarted),
			timeFinished: text(s.timeFinished),
			failureReason: text(s.failureReason),
			progressCurrent: num(s.progressCurrent),
			progressTotal: num(s.progressTotal)
		})
	);
	const latest = new Map<string, StepRunView>();
	for (const s of all) {
		const current = latest.get(s.stepId);
		if (!current || (parseServerTime(s.timeQueued) ?? 0) >= (parseServerTime(current.timeQueued) ?? 0)) {
			latest.set(s.stepId, s);
		}
	}
	return {
		guid: String(w.guid),
		flowId: String(w.flowId),
		flowRevision: num(w.flowRevision) ?? 0,
		state: String(w.state) as RunState,
		startedAt: text(w.startedAt),
		finishedAt: text(w.finishedAt),
		dispatchedBy: String(w.dispatchedBy ?? ''),
		steps: [...latest.values()].sort((a, b) => a.stepId.localeCompare(b.stepId)),
		log: ((w.log as Wire[]) ?? []).map((l) => ({
			at: String(l.at ?? ''),
			stepId: text(l.stepId),
			severity: String(l.severity ?? 'info'),
			message: String(l.message ?? '')
		}))
	};
}

export const isTerminal = (state: string): boolean => ['completed', 'failed', 'cancelled'].includes(state);

export function countLine(steps: Array<{ state: StepState }>): string {
	const n = (s: StepState) => steps.filter((x) => x.state === s).length;
	const parts = [`${n('completed')} completed`, `${n('failed')} failed`, `${n('running')} running`, `${n('queued')} queued`];
	if (n('paused')) parts.push(`${n('paused')} paused`);
	if (n('cancelled')) parts.push(`${n('cancelled')} cancelled`);
	return parts.join(' · ');
}

const pad = (n: number, w = 2) => String(Math.floor(n)).padStart(w, '0');

/** Step durations as UI-002 shows them: `12:04.7`. */
export function formatDuration(ms: number): string {
	const tenths = Math.floor(ms / 100) % 10;
	const seconds = Math.floor(ms / 1000);
	return `${pad(seconds / 60)}:${pad(seconds % 60)}.${tenths}`;
}

/** The wave clock: `00:24:17`. */
export function formatClock(ms: number): string {
	const s = Math.max(0, Math.floor(ms / 1000));
	return `${pad(s / 3600)}:${pad((s % 3600) / 60)}:${pad(s % 60)}`;
}

export const timeOfDay = (value: string | null): string => (value ? value.slice(11, 19) : '—');

/** Finished steps are measured from their own timestamps; running ones up to `nowMs`. */
export function stepDurationMs(step: StepRunView, nowMs: number): number | null {
	const started = parseServerTime(step.timeStarted);
	if (started === null) return null;
	const finished = parseServerTime(step.timeFinished);
	return (finished ?? nowMs) - started;
}

/** FR-028: every join (ALL_MUST_SUCCEED in v1) whose required input did not complete. */
export function failedJoins(
	edges: EdgeRef[],
	stateOf: (stepId: string) => StepState | undefined
): Array<{ target: string; failedInputs: string[] }> {
	return joinTargets(edges)
		.map((target) => ({
			target,
			failedInputs: incomingSources(edges, target).filter((s) => {
				const state = stateOf(s);
				return state === 'failed' || state === 'cancelled';
			})
		}))
		.filter((j) => j.failedInputs.length > 0);
}
