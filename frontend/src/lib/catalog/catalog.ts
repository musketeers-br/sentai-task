// The Task catalog's view models (spec 007 data-model.md). This module and src/lib/api/client.ts
// are the only ones that know the spec 006 wire shape; components receive only these types.
// Nothing here decides which tasks exist, what they are or whether they are destructive: every
// value is the API's, and a value the API did not send stays absent (FR-007, FR-019).
import type { ApiError, PlatformStatus } from '$lib/api/client';
import { consequence } from '$lib/flow/consequence';
import type { StepTypeInfo } from '$lib/flow/document';

export interface WireUnavailable {
	read: string;
	fields: string[];
	httpStatus: number | string;
	platformStatus?: PlatformStatus;
}

/**
 * A spec 006 catalog item. `className`, `isDestructive` and `lastRun` are listed only so the
 * tests can prove they are never read (the old list `Type` and the deprecated aliases).
 */
export interface WireCatalogTask {
	taskId: number | string;
	name: string;
	namespace: string;
	class?: string;
	runAsUser?: string;
	timePeriod?: string;
	nextRun?: string;
	lastStarted?: string;
	lastFinished?: string;
	status?: string;
	lastError?: string;
	suspended?: boolean;
	destructive?: boolean;
	destructiveUnknown?: boolean;
	origin?: TaskOrigin;
	recentRuns?: WireRecentRun[];
	unavailable?: WireUnavailable[];
	/** Spec 023: the platform's own Description, absent when it sent none. */
	description?: string;
	className?: string;
	isDestructive?: boolean;
	lastRun?: string;
}

/** One row of the platform's task history, as spec 006 R-4 passes it through. */
export interface WireRecentRun {
	LastStart: string;
	Completed: string;
	Status: string;
	Result: string;
	Username: string;
	LogDatetime: string;
}

/** Present only on tasks whose name follows `SentaiTask: <flowId> <flow name>` (spec 015) or the
 * legacy `SentaiTask: <flowId>#<stepId>` (spec 006, which alone carries `stepId`). */
export interface TaskOrigin {
	flowId: string;
	stepId?: string;
	flowExists: boolean;
}

export interface RecentRun {
	start: string;
	completed: string;
	status: string;
	result: string;
	user: string;
	loggedAt: string;
}

/** Spec 023: over every task the list read enumerated, before any filter. */
export interface CatalogCounts {
	suspended: number;
	destructive: number;
	unclassified: number;
}

export interface WireCatalogPage {
	total: number | string;
	matched: number | string;
	items: WireCatalogTask[];
	counts?: { suspended: number | string; destructive: number | string; unclassified: number | string };
}

export interface UnavailableReason {
	read: string;
	httpStatus: number;
	text: string;
}

export type Value<T> =
	| { kind: 'value'; value: T }
	| { kind: 'unavailable'; reason: UnavailableReason }
	| { kind: 'absent' };

export interface CatalogTaskView {
	taskId: number;
	name: string;
	namespace: string;
	className: Value<string>;
	runAsUser: Value<string>;
	timePeriod: Value<string>;
	nextRun: Value<string>;
	lastStarted: Value<string>;
	lastFinished: Value<string>;
	status: Value<string>;
	lastError: Value<string>;
	suspended: Value<boolean>;
	destructive: 'yes' | 'no' | 'unknown';
	/** Spec 023 FR-017: the platform's description. */
	description: Value<string>;
	origin?: TaskOrigin;
	/** Item read only: absent → no section, [] → "No runs reported" (US-1.7). */
	recentRuns?: RecentRun[];
}

export interface CatalogPage {
	total: number;
	matched: number;
	/** Spec 023 FR-015: absent when the API sent none — never shown as 0. */
	counts: Value<CatalogCounts>;
	items: CatalogTaskView[];
}

const NO_REASON = 'no reason given';

/** The platform's own words: its `errors[].error` joined by "; ", or "no reason given". */
function platformText(status: PlatformStatus | undefined): string {
	const text = (status?.errors ?? []).map((e) => e.error).join('; ');
	return text || NO_REASON;
}

export function fromWireCatalogTask(w: WireCatalogTask): CatalogTaskView {
	const reasons = new Map<string, UnavailableReason>();
	for (const u of w.unavailable ?? []) {
		const reason = { read: u.read, httpStatus: Number(u.httpStatus), text: platformText(u.platformStatus) };
		for (const field of u.fields) reasons.set(field, reason);
	}

	function value<K extends keyof WireCatalogTask>(key: K): Value<NonNullable<WireCatalogTask[K]>> {
		const reason = reasons.get(key);
		if (reason) return { kind: 'unavailable', reason };
		const v = w[key];
		return v === undefined || v === null ? { kind: 'absent' } : { kind: 'value', value: v as NonNullable<WireCatalogTask[K]> };
	}

	return {
		taskId: Number(w.taskId),
		name: w.name,
		namespace: w.namespace,
		className: value('class'),
		runAsUser: value('runAsUser'),
		timePeriod: value('timePeriod'),
		nextRun: value('nextRun'),
		lastStarted: value('lastStarted'),
		lastFinished: value('lastFinished'),
		status: value('status'),
		lastError: value('lastError'),
		suspended: value('suspended'),
		destructive: w.destructiveUnknown || w.destructive === undefined ? 'unknown' : w.destructive ? 'yes' : 'no',
		description: w.description ? { kind: 'value', value: w.description } : { kind: 'absent' },
		...(w.origin ? { origin: { ...w.origin } } : {}),
		...(Array.isArray(w.recentRuns)
			? {
					recentRuns: w.recentRuns.map((r) => ({
						start: r.LastStart,
						completed: r.Completed,
						status: r.Status,
						result: r.Result,
						user: r.Username,
						loggedAt: r.LogDatetime
					}))
				}
			: {})
	};
}

export type OriginMark = { label: string; flowId: string } | { label: 'flow not found'; flowId: null; title: string };

/** FR-009: the SentaiTask mark, a link to the flow only when the API says it still exists. */
export function originMark(task: CatalogTaskView): OriginMark | null {
	if (!task.origin) return null;
	const label = task.origin.stepId ? `flow ${task.origin.flowId} · step ${task.origin.stepId}` : `flow ${task.origin.flowId}`;
	return task.origin.flowExists ? { label, flowId: task.origin.flowId } : { label: 'flow not found', flowId: null, title: label };
}

/** The detail's fields (FR-006), in the order shown; recent runs follow as their own section. */
export const DETAIL_FIELDS = [
	{ key: 'name', label: 'Name' },
	{ key: 'taskId', label: 'ID' },
	{ key: 'namespace', label: 'Namespace' },
	{ key: 'className', label: 'Class' },
	{ key: 'description', label: 'Description' },
	{ key: 'runAsUser', label: 'Run as user' },
	{ key: 'timePeriod', label: 'Time period' },
	{ key: 'nextRun', label: 'Next run' },
	{ key: 'lastStarted', label: 'Last started' },
	{ key: 'lastFinished', label: 'Last finished' },
	{ key: 'status', label: 'Status' },
	{ key: 'lastError', label: 'Last error' },
	{ key: 'suspended', label: 'Suspended' },
	{ key: 'destructive', label: 'Destructiveness' },
	{ key: 'origin', label: 'Origin' }
] as const;

export function fromWireCatalogPage(w: WireCatalogPage): CatalogPage {
	return {
		total: Number(w.total),
		matched: Number(w.matched),
		counts: w.counts
			? {
					kind: 'value',
					value: {
						suspended: Number(w.counts.suspended),
						destructive: Number(w.counts.destructive),
						unclassified: Number(w.counts.unclassified)
					}
				}
			: { kind: 'absent' },
		items: (w.items ?? []).map(fromWireCatalogTask)
	};
}

/** Spec 023 FR-015: how long ago the list was read (milliseconds since the epoch). */
export function ageText(readAt: number, now: number): string {
	const seconds = Math.max(0, Math.floor((now - readAt) / 1000));
	if (seconds < 60) return `updated ${seconds} s ago`;
	return `updated ${Math.floor(seconds / 60)} min ago`;
}

/** Spec 023 FR-016: the order and the API's totals; no total when the API sent none. */
export function footerText(page: CatalogPage): string {
	if (page.counts.kind !== 'value') return 'sorted by next run';
	const c = page.counts.value;
	return `sorted by next run · ${c.destructive} destructive · ${c.suspended} suspended · ${c.unclassified} unclassified`;
}

export type DestructiveReason = { kind: 'stepType'; text: string } | { kind: 'flow'; flowId: string };

/**
 * Spec 023 FR-017 (research R-4): why a destructive task is destructive, as the step-type catalog
 * states it — the matched type's consequence with its declared defaults — or, for a SentaiTask
 * flow task, the flow whose step makes it so. Nothing is said about a task that is not destructive.
 */
export function destructiveReason(task: CatalogTaskView, registry: readonly StepTypeInfo[]): DestructiveReason | null {
	if (task.destructive !== 'yes') return null;
	const entry = matchedStepType(task, registry);
	if (entry) return { kind: 'stepType', text: consequence(entry.type, declaredDefaults(entry)) };
	if (task.origin) return { kind: 'flow', flowId: task.origin.flowId };
	return null;
}

/** Spec 023 FR-020a: the catalog reports no SentaiTask origin for this task. */
export function outsideMark(task: CatalogTaskView): boolean {
	return !task.origin;
}

export interface StepDraft {
	type: string;
	namespace?: string;
	runAsUser?: string;
}

export type AddToFlow = { ok: true; step: StepDraft } | { ok: false; reason: string };

/**
 * Spec 023 FR-018 (research R-6): the step a catalog task becomes — the declared type whose class
 * is the task's, with the task's namespace and run-as user. The catalog carries no task settings,
 * so the parameters are the type's defaults, as when it is dragged from the palette.
 */
export function stepFromTask(task: CatalogTaskView, registry: readonly StepTypeInfo[]): AddToFlow {
	if (task.className.kind !== 'value') return { ok: false, reason: 'the task class could not be read' };
	const entry = matchedStepType(task, registry);
	if (!entry) return { ok: false, reason: 'no step type declares this class' };
	if (!entry.available) return { ok: false, reason: 'this step type is not supported in v1' };
	return {
		ok: true,
		step: {
			type: entry.type,
			namespace: task.namespace,
			...(task.runAsUser.kind === 'value' && task.runAsUser.value ? { runAsUser: task.runAsUser.value } : {})
		}
	};
}

function matchedStepType(task: CatalogTaskView, registry: readonly StepTypeInfo[]): StepTypeInfo | undefined {
	if (task.className.kind !== 'value' || !task.className.value) return undefined;
	const className = task.className.value;
	return registry.find((t) => t.className !== '' && t.className === className);
}

function declaredDefaults(entry: StepTypeInfo): Record<string, unknown> {
	return Object.fromEntries((entry.parameters ?? []).filter((p) => p.default !== undefined).map((p) => [p.name, p.default]));
}

const TIMESTAMP = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}/;

/** Research R-3 buckets: timestamps, other text, "" (none reported), absent/unavailable. */
function bucket(nextRun: Value<string>): number {
	if (nextRun.kind !== 'value') return 3;
	if (nextRun.value === '') return 2;
	return TIMESTAMP.test(nextRun.value) ? 0 : 1;
}

/**
 * Display order only (FR-004): by next run ascending, tasks without one last. Stable, and never
 * reformats a value; the format `YYYY-MM-DD HH:MM:SS` sorts chronologically as text.
 */
export function orderByNextRun(items: CatalogTaskView[]): CatalogTaskView[] {
	const text = (t: CatalogTaskView) => (t.nextRun.kind === 'value' ? t.nextRun.value : '');
	return [...items].sort(
		(a, b) =>
			bucket(a.nextRun) - bucket(b.nextRun) ||
			(text(a) < text(b) ? -1 : text(a) > text(b) ? 1 : 0) ||
			(a.name < b.name ? -1 : a.name > b.name ? 1 : 0) ||
			a.taskId - b.taskId
	);
}

/** `HTTP <status> — <detail | platform errors | "no reason given">`, never paraphrased. */
export function refusalText(error: ApiError): string {
	switch (error.kind) {
		case 'problem':
			return `HTTP ${error.status} — ${error.detail || platformText(error.platformStatus)}`;
		case 'validation':
			return `HTTP ${error.status} — ${error.report.errors.map((f) => f.message).join('; ') || NO_REASON}`;
		case 'network':
			return error.message;
		case 'unauthorized':
			return 'Your session expired. Sign in again to continue.';
	}
}

/** The platform's status verbatim; "1" is its success code, labelled so it reads as one. */
export function statusLabel(status: string): string {
	return status === '1' ? 'OK (1)' : status;
}

export interface CatalogFilters {
	q: string;
	namespace: string;
	state: 'all' | 'scheduled' | 'suspended';
	destructiveOnly: boolean;
	/** Spec 023 FR-015: only the tasks the step-type catalog cannot classify. */
	unclassifiedOnly: boolean;
}

export const NO_FILTERS: CatalogFilters = { q: '', namespace: 'all', state: 'all', destructiveOnly: false, unclassifiedOnly: false };

/**
 * The query the API filters with (FR-005): defaults are omitted, so an unfiltered read is a bare
 * `GET /catalog/tasks`. The screen never filters or counts on its own.
 */
export function catalogQuery(filters: CatalogFilters): string {
	const params = new URLSearchParams();
	if (filters.q.trim()) params.set('q', filters.q.trim());
	if (filters.namespace !== 'all') params.set('namespace', filters.namespace);
	if (filters.state !== 'all') params.set('filter', filters.state);
	if (filters.destructiveOnly) params.set('destructiveOnly', '1');
	if (filters.unclassifiedOnly) params.set('unclassifiedOnly', '1');
	const query = params.toString();
	return query ? `?${query}` : '';
}

const STATES: readonly CatalogFilters['state'][] = ['all', 'scheduled', 'suspended'];

/** Spec 023: the filters an address preselects (Overview's "Show in catalog"); unknown values are ignored. */
export function filtersFromUrl(url: URL): CatalogFilters {
	const state = url.searchParams.get('filter');
	return {
		...NO_FILTERS,
		state: STATES.includes(state as CatalogFilters['state']) ? (state as CatalogFilters['state']) : 'all',
		destructiveOnly: url.searchParams.get('destructiveOnly') === '1',
		unclassifiedOnly: url.searchParams.get('unclassifiedOnly') === '1'
	};
}

/** The same address with these filters; defaults are left out, everything else is kept. */
export function withFilters(url: URL, filters: CatalogFilters): URL {
	const next = new URL(url);
	if (filters.state === 'all') next.searchParams.delete('filter');
	else next.searchParams.set('filter', filters.state);
	for (const key of ['destructiveOnly', 'unclassifiedOnly'] as const) {
		if (filters[key]) next.searchParams.set(key, '1');
		else next.searchParams.delete(key);
	}
	return next;
}

/** Research R-2: "all" plus the namespaces an unfiltered read returned, in the order it did. */
export function namespaceOptions(page: CatalogPage): string[] {
	return ['all', ...new Set(page.items.map((t) => t.namespace))];
}

/** Latest-request-wins: a slower, older answer never overwrites a newer one. */
export function createSequence() {
	let latest = 0;
	return {
		next: () => ++latest,
		isLatest: (n: number) => n === latest
	};
}

/**
 * FR-008: exactly one of Suspend or Resume, chosen from the API's `suspended`; none when the
 * value is unavailable or absent (its reason is shown instead). No permission is guessed: the
 * button shows, and the platform decides.
 */
export function suspendActionFor(task: CatalogTaskView): 'suspend' | 'resume' | null {
	if (task.suspended.kind !== 'value') return null;
	return task.suspended.value ? 'resume' : 'suspend';
}

export type SuspendActionState =
	| { name: 'idle' }
	| { name: 'confirming'; suspended: boolean }
	| { name: 'pending'; suspended: boolean }
	| { name: 'error'; message: string };

export type SuspendActionEvent =
	| { type: 'toggle'; suspended: boolean }
	| { type: 'cancel' }
	| { type: 'confirm' }
	| { type: 'send'; suspended: boolean }
	| { type: 'ok'; task: CatalogTaskView }
	| { type: 'fail'; error: ApiError };

export interface SuspendToggle {
	/** The API's suspended value; null when it is unavailable (the toggle is then disabled). */
	checked: boolean | null;
	confirm: { action: 'suspend' | 'resume'; title: string; body: string };
}

/**
 * Spec 023 FR-020: one switch for Suspend/Resume, from the API's `suspended`, and the simple
 * confirmation it asks (not the typed gate of destructive steps). No permission is guessed.
 */
export function suspendToggle(task: CatalogTaskView): SuspendToggle {
	const checked = task.suspended.kind === 'value' ? task.suspended.value : null;
	const action = checked ? 'resume' : 'suspend';
	const flowNote = task.origin
		? ` It runs flow ${task.origin.flowId} on its schedule: the scheduled runs of that flow stop until it is resumed.`
		: '';
	return {
		checked,
		confirm:
			action === 'suspend'
				? { action, title: `Suspend “${task.name}”?`, body: `The Task Manager will not run this task until it is resumed.${flowNote}` }
				: { action, title: `Resume “${task.name}”?`, body: 'The Task Manager runs this task again on its schedule.' }
	};
}

/**
 * Data-model §CatalogScreen state. After any answer the shown state is the API's: a success
 * carries the re-read task and the list is re-read (FR-011); a failure is shown verbatim and both
 * the item and the list are re-read. Nothing is retried on the operator's behalf (R-5).
 */
export function reduceSuspendAction(
	state: SuspendActionState,
	event: SuspendActionEvent
): { state: SuspendActionState; task?: CatalogTaskView; reread: Array<'item' | 'list'> } {
	switch (event.type) {
		case 'toggle':
			// Spec 023: nothing is sent until the operator confirms.
			return state.name === 'pending' ? { state, reread: [] } : { state: { name: 'confirming', suspended: event.suspended }, reread: [] };
		case 'cancel':
			return state.name === 'confirming' ? { state: { name: 'idle' }, reread: [] } : { state, reread: [] };
		case 'confirm':
			return state.name === 'confirming' ? { state: { name: 'pending', suspended: state.suspended }, reread: [] } : { state, reread: [] };
		case 'send':
			return state.name === 'pending' ? { state, reread: [] } : { state: { name: 'pending', suspended: event.suspended }, reread: [] };
		case 'ok':
			return { state: { name: 'idle' }, task: event.task, reread: ['list'] };
		case 'fail':
			return { state: { name: 'error', message: refusalText(event.error) }, reread: ['item', 'list'] };
	}
}
