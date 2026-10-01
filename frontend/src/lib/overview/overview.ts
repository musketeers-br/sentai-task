// Spec 019: the Overview screen's pure logic over spec 018's API — cards from the summary, the
// detail view's table, the last on-demand report per card and the auto-refresh timer. Every value
// is the API's; this module only formats and orders it (FR-005) and never names a host CPU,
// memory or log (FR-006). Errors are values: each card and reading carries its own outcome.
import type { PlatformStatus } from '$lib/api/client';
import type { Finding, ValidationReport } from '$lib/flow/report';

export type AreaGroup = 'instance' | 'report';

/** Fixed display labels for spec 018's area ids (data-model §1). */
export const AREA_LABELS: Record<string, string> = {
	processes: 'Processes',
	locks: 'Locks',
	memory: 'Shared memory',
	activity: 'Activity',
	devices: 'Devices',
	licenses: 'Licenses',
	'web-sessions': 'Web sessions',
	security: 'Security posture',
	'web-apps': 'Web applications',
	alerts: 'System alerts',
	secrets: 'Secrets'
};

export function areaLabel(area: string): string {
	return AREA_LABELS[area] ?? area;
}

// ---------- summary → cards ----------

export interface WireProblem {
	title?: string;
	detail?: string;
	httpStatus?: number;
	platformStatus?: PlatformStatus;
}

export interface WireAreaEntry {
	area: string;
	group: AreaGroup;
	outcome: 'ok' | 'refused' | 'unreachable';
	readAt: string;
	headline: Record<string, unknown> | null;
	problem: WireProblem | null;
	stepType: string | null;
}

export interface WireSummary {
	readAt: string;
	areas: WireAreaEntry[];
}

export type CardState =
	| { kind: 'ok'; readAt: string; headline: Record<string, unknown> }
	| { kind: 'refused'; readAt: string; httpStatus: number; title: string; detail: string; platformStatus?: PlatformStatus }
	| { kind: 'unreachable'; readAt: string; detail: string };

export interface CardReport {
	ranAt: string;
	state: 'completed' | 'failed';
	counts: { high: number; medium: number; info: number };
	failureReason: string;
	report: unknown;
}

export interface AreaCardView {
	area: string;
	label: string;
	group: AreaGroup;
	state: CardState;
	stepType: string | null;
	headlineLines: string[];
	report: CardReport | null;
}

export function fromWireSummary(w: WireSummary): AreaCardView[] {
	return w.areas.map((e) => {
		const state = cardState(e);
		return {
			area: e.area,
			label: areaLabel(e.area),
			group: e.group,
			state,
			stepType: e.stepType ?? null,
			headlineLines: state.kind === 'ok' ? headlineLines(e.area, state.headline) : [],
			report: null
		};
	});
}

function cardState(e: WireAreaEntry): CardState {
	if (e.outcome === 'ok') return { kind: 'ok', readAt: e.readAt, headline: e.headline ?? {} };
	const p = e.problem ?? {};
	if (e.outcome === 'unreachable') return { kind: 'unreachable', readAt: e.readAt, detail: p.detail ?? '' };
	return {
		kind: 'refused',
		readAt: e.readAt,
		httpStatus: p.httpStatus ?? 0,
		title: p.title ?? '',
		detail: p.detail ?? '',
		...(p.platformStatus ? { platformStatus: p.platformStatus } : {})
	};
}

/** `HTTP <status> — <the platform's words>`, verbatim (the spec 009 wording). */
export function refusalLine(state: CardState): string {
	if (state.kind === 'ok') return '';
	if (state.kind === 'unreachable') return state.detail || 'The platform did not answer.';
	const words = state.detail || state.platformStatus?.summary || 'no reason given';
	return `HTTP ${state.httpStatus} — ${words}`;
}

const NUMBER = new Intl.NumberFormat('en-US');

function n(value: unknown): string {
	return typeof value === 'number' ? NUMBER.format(value) : value === null || value === undefined || value === '' ? '—' : String(value);
}

/** `1 lock`, `36 locks`, `— locks`. */
function count(value: unknown, singular: string, plural = `${singular}s`): string {
	return `${n(value)} ${value === 1 ? singular : plural}`;
}

function pct(value: unknown): string {
	return typeof value === 'number' ? `${NUMBER.format(value)}%` : '—';
}

/** One or two lines per area, formatting the API's numbers only (FR-005). */
export function headlineLines(area: string, h: Record<string, unknown>): string[] {
	const obj = (v: unknown) => (v !== null && typeof v === 'object' ? (v as Record<string, unknown>) : null);
	switch (area) {
		case 'processes': {
			const busiest = obj(h.busiest);
			return [count(h.count, 'process', 'processes'), ...(busiest ? [`Busiest: ${n(busiest.Routine)} (pid ${n(busiest.Pid)}) · ${n(busiest.Commands)} commands`] : [])];
		}
		case 'locks':
			return [count(h.count, 'lock')];
		case 'memory': {
			const most = obj(h.mostUsed);
			return [`${pct(h.usedPercent)} of shared memory used`, ...(most ? [`Most used: ${n(most.description)} ${pct(most.usedPercent)}`] : [])];
		}
		case 'activity':
			return [`Up ${n(h.uptime)} · last backup ${n(h.lastBackup)}`, `${n(h.globalRefsPerSecond)} global refs/s · ${count(h.busyProcesses, 'busy process', 'busy processes')}`];
		case 'devices':
			return [count(h.count, 'device')];
		case 'licenses':
			return [`${n(h.inUse)} of ${n(h.authorized)} license units in use`];
		case 'web-sessions':
			return [count(h.count, 'web session')];
		case 'security':
			return [`${n(h.enabledAccounts)} of ${n(h.accounts)} accounts enabled`];
		case 'web-apps':
			return [count(h.count, 'web application')];
		case 'alerts':
			return [`${count(h.seriousAlerts, 'serious alert')} · ${count(h.applicationErrors, 'application error')}`];
		case 'secrets':
			return [count(h.collections, 'wallet collection')];
		default:
			return Object.entries(h).map(([k, v]) => `${k}: ${n(v)}`);
	}
}

/** *Refresh*: the new summary, each card keeping its last on-demand report (clarification Q2). */
export function withSummary(previous: AreaCardView[], next: AreaCardView[]): AreaCardView[] {
	const kept = new Map(previous.map((c) => [c.area, c.report]));
	return next.map((c) => ({ ...c, report: kept.get(c.area) ?? null }));
}

export function withCardReport(cards: AreaCardView[], area: string, report: CardReport): AreaCardView[] {
	return cards.map((c) => (c.area === area ? { ...c, report } : c));
}

export function canSchedule(card: AreaCardView): boolean {
	return card.stepType !== null && card.stepType !== '';
}

export function isInstanceArea(cards: AreaCardView[] | null, area: string): boolean {
	if (cards) return cards.some((c) => c.area === area && c.group === 'instance');
	return ['processes', 'locks', 'memory', 'activity', 'devices', 'licenses', 'web-sessions'].includes(area);
}

// ---------- on-demand reports ----------

export interface WireOnDemandReport {
	stepType: string;
	state: 'completed' | 'failed';
	failureReason: string;
	report: { summary?: { high?: number; medium?: number; info?: number } } | null;
	ranAt: string;
}

export function fromWireOnDemand(w: WireOnDemandReport): CardReport {
	const s = w.report?.summary ?? {};
	return {
		ranAt: w.ranAt,
		state: w.state,
		counts: { high: s.high ?? 0, medium: s.medium ?? 0, info: s.info ?? 0 },
		failureReason: w.failureReason ?? '',
		report: w.report
	};
}

/** The validator's PARAM_* errors as the findings `ParameterForm` shows on their fields. */
export function paramFindings(report: ValidationReport): Finding[] {
	return report.errors;
}

export interface WireAreaFlow {
	flow: { id: string | number };
	validation: ValidationReport;
}

export function fromWireAreaFlow(w: WireAreaFlow): { flowId: string; hasErrors: boolean } {
	return { flowId: String(w.flow.id), hasErrors: (w.validation?.errors?.length ?? 0) > 0 };
}

// ---------- detail views ----------

export interface ReadingView {
	area: string;
	readAt: string;
	columns: string[];
	rows: Record<string, unknown>[];
	computed: string[];
	parts: Record<string, unknown> | null;
}

export interface WireReading {
	area: string;
	readAt: string;
	columns: string[];
	rows: Record<string, unknown>[];
	computed?: string[];
	parts?: Record<string, unknown>;
}

export function fromWireReading(w: WireReading): ReadingView {
	return { area: w.area, readAt: w.readAt, columns: w.columns, rows: w.rows, computed: w.computed ?? [], parts: w.parts ?? null };
}

export type ReadingState =
	| { kind: 'loading' }
	| { kind: 'list'; view: ReadingView }
	| { kind: 'refused'; text: string }
	| { kind: 'unreachable'; text: string };

export interface TableState {
	sortBy: string | null;
	descending: boolean;
	filter: string;
}

export const NO_TABLE_STATE: TableState = { sortBy: null, descending: false, filter: '' };

/** Headings: the API's names, except the one that could read as host CPU (FR-006). */
export function columnLabel(column: string): string {
	return column === 'CPUTime' ? 'CPU time (process)' : column;
}

function compare(a: unknown, b: unknown): number {
	const empty = (v: unknown) => v === null || v === undefined || v === '';
	if (empty(a) && empty(b)) return 0;
	if (empty(a)) return 1;
	if (empty(b)) return -1;
	if (typeof a === 'number' && typeof b === 'number') return a - b;
	if (typeof a === 'boolean' && typeof b === 'boolean') return Number(a) - Number(b);
	return String(a).localeCompare(String(b), 'en', { sensitivity: 'base', numeric: true });
}

/** Every row the API returned, filtered by text and sorted; nothing is dropped silently. */
export function visibleRows(view: ReadingView, state: TableState): Record<string, unknown>[] {
	const needle = state.filter.trim().toLowerCase();
	const rows = needle
		? view.rows.filter((row) => view.columns.some((c) => row[c] !== null && row[c] !== undefined && String(row[c]).toLowerCase().includes(needle)))
		: [...view.rows];
	if (state.sortBy) {
		const key = state.sortBy;
		rows.sort((a, b) => {
			const r = compare(a[key], b[key]);
			// Empty values stay last in both directions.
			const emptyA = a[key] === null || a[key] === undefined || a[key] === '';
			const emptyB = b[key] === null || b[key] === undefined || b[key] === '';
			if (emptyA || emptyB) return r;
			return state.descending ? -r : r;
		});
	}
	return rows;
}

export function rowCountLine(total: number, shown: number): string {
	const rows = `${NUMBER.format(total)} row${total === 1 ? '' : 's'}`;
	return shown === total ? rows : `${rows} · ${NUMBER.format(shown)} shown`;
}

export function cellText(value: unknown): string {
	if (value === null || value === undefined || value === '') return '—';
	if (typeof value === 'number') return NUMBER.format(value);
	return String(value);
}

// ---------- auto-refresh ----------

export interface AutoRefreshDeps {
	intervalMs: number;
	read: () => Promise<void>;
	isVisible: () => boolean;
	setTimer: (fn: () => void, ms: number) => unknown;
	clearTimer: (handle: unknown) => void;
}

export interface AutoRefresh {
	readonly on: boolean;
	start(): void;
	stop(): void;
	/** Call on `visibilitychange`: a read resumes as soon as the page is visible again. */
	visibilityChanged(): void;
}

/** Off by default; one read in flight at most; no read while the page is hidden (FR-008). */
export function createAutoRefresh(deps: AutoRefreshDeps): AutoRefresh {
	let on = false;
	let inFlight = false;
	let timer: unknown = null;

	function schedule() {
		if (timer !== null) deps.clearTimer(timer);
		timer = on ? deps.setTimer(tick, deps.intervalMs) : null;
	}

	async function tick() {
		timer = null;
		if (!on) return;
		if (deps.isVisible() && !inFlight) {
			inFlight = true;
			try {
				await deps.read();
			} finally {
				inFlight = false;
			}
		}
		schedule();
	}

	return {
		get on() {
			return on;
		},
		start() {
			if (on) return;
			on = true;
			schedule();
		},
		stop() {
			on = false;
			schedule();
		},
		visibilityChanged() {
			if (!on || !deps.isVisible() || inFlight) return;
			if (timer !== null) deps.clearTimer(timer);
			timer = null;
			void tick();
		}
	};
}
