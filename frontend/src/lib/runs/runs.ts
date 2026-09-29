// Spec 012 US2 (plan D-6, D-7): the Runs screen's pure logic — the query in the address, the run
// summaries as GET /runs returns them, and pages merged by their stable cursor.
import { formatClock, type RunState } from '$lib/run/run';

export const RUN_STATES: RunState[] = ['running', 'completed', 'failed', 'cancelled'];
export const DEFAULT_PAGE_SIZE = 50;

export interface RunsQuery {
	flow?: string;
	state?: RunState;
	/** 1–200; the default is 50 (tests use a small page to exercise paging). */
	pageSize?: number;
}

export interface StepCounts {
	queued: number;
	running: number;
	paused: number;
	completed: number;
	failed: number;
	cancelled: number;
}

export interface RunSummaryView {
	seq: number;
	guid: string;
	flowId: string;
	flowName: string;
	flowRevision: number;
	state: RunState;
	startedAt: string | null;
	finishedAt: string | null;
	dispatchedBy: string;
	totalDurationMs: number;
	stepCounts: StepCounts;
}

// The filters use their own parameters: `flow` already names the flow open in the editor, which
// the page loads from the address (spec 010), so a filter must never change it.
export function queryFromUrl(url: URL): RunsQuery {
	const q: RunsQuery = {};
	const flow = url.searchParams.get('runsFlow');
	if (flow) q.flow = flow;
	const state = url.searchParams.get('runsState');
	if (state && (RUN_STATES as string[]).includes(state)) q.state = state as RunState;
	const size = Number(url.searchParams.get('pageSize'));
	if (Number.isInteger(size) && size >= 1 && size <= 200) q.pageSize = size;
	return q;
}

/** The same address showing `query` on the Runs screen (other parameters dropped, `run` too). */
export function urlForQuery(url: URL, query: RunsQuery): URL {
	const next = new URL(url);
	for (const key of ['runsFlow', 'runsState', 'run', 'from']) next.searchParams.delete(key);
	next.searchParams.set('view', 'runs');
	if (query.flow) next.searchParams.set('runsFlow', query.flow);
	if (query.state) next.searchParams.set('runsState', query.state);
	return next;
}

/** The run view for `run`, opened from the Runs screen: its flow in the editor, the filters kept. */
export function urlForRun(url: URL, run: Pick<RunSummaryView, 'guid' | 'flowId'>): URL {
	const next = new URL(url);
	next.searchParams.delete('view');
	next.searchParams.set('flow', run.flowId);
	next.searchParams.set('run', run.guid);
	next.searchParams.set('from', 'runs');
	return next;
}

/** GET /runs query string for one page. */
export function pageParams(query: RunsQuery, before: number | null): string {
	const p = new URLSearchParams();
	if (query.flow) p.set('flowId', query.flow);
	if (query.state) p.set('state', query.state);
	p.set('limit', String(query.pageSize ?? DEFAULT_PAGE_SIZE));
	if (before !== null) p.set('before', String(before));
	return p.toString();
}

type Wire = Record<string, unknown>;
const n = (v: unknown): number => (Number.isFinite(Number(v)) ? Number(v) : 0);
const t = (v: unknown): string | null => (v === null || v === undefined || v === '' ? null : String(v));

export function fromWireRunSummary(w: Wire): RunSummaryView {
	const c = (w.stepCounts ?? {}) as Wire;
	return {
		seq: n(w.seq),
		guid: String(w.guid),
		flowId: String(w.flowId),
		flowName: String(w.flowName ?? ''),
		flowRevision: n(w.flowRevision),
		state: String(w.state) as RunState,
		startedAt: t(w.startedAt),
		finishedAt: t(w.finishedAt),
		dispatchedBy: String(w.dispatchedBy ?? ''),
		totalDurationMs: n(w.totalDurationMs),
		stepCounts: {
			queued: n(c.queued),
			running: n(c.running),
			paused: n(c.paused),
			completed: n(c.completed),
			failed: n(c.failed),
			cancelled: n(c.cancelled)
		}
	};
}

/** Appends `next` to `current` by seq, dropping any run already shown (FR-008). */
export function mergePage(current: readonly RunSummaryView[], next: readonly RunSummaryView[]): RunSummaryView[] {
	const seen = new Set(current.map((r) => r.seq));
	return [...current, ...next.filter((r) => !seen.has(r.seq))];
}

/** The cursor for the page after `items`, or null when `items` was a short (last) page. */
export function nextCursor(items: readonly RunSummaryView[], pageSize: number): number | null {
	return items.length >= pageSize && items.length > 0 ? items[items.length - 1].seq : null;
}

export function countsLine(c: StepCounts): string {
	const parts = [`${c.completed} completed`, `${c.failed} failed`];
	if (c.cancelled) parts.push(`${c.cancelled} cancelled`);
	const live = c.running + c.queued + c.paused;
	if (live) parts.push(`${live} not finished`);
	return parts.join(' · ');
}

export const durationText = (ms: number): string => formatClock(ms);

export function emptyText(query: RunsQuery): string {
	if (query.flow && query.state) return `No ${query.state} runs for this flow.`;
	if (query.flow) return 'No runs for this flow yet.';
	if (query.state) return `No ${query.state} runs.`;
	return 'No runs yet. Run a flow and it appears here.';
}
