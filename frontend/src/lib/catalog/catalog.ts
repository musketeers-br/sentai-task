// The Task catalog's view models (spec 007 data-model.md). This module and src/lib/api/client.ts
// are the only ones that know the spec 006 wire shape; components receive only these types.
// Nothing here decides which tasks exist, what they are or whether they are destructive: every
// value is the API's, and a value the API did not send stays absent (FR-007, FR-019).
import type { ApiError, PlatformStatus } from '$lib/api/client';

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

/** Present only on tasks whose name follows `SentaiTask: <flowId>#<stepId>` (spec 006). */
export interface TaskOrigin {
	flowId: string;
	stepId: string;
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

export interface WireCatalogPage {
	total: number | string;
	matched: number | string;
	items: WireCatalogTask[];
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
	origin?: TaskOrigin;
	/** Item read only: absent → no section, [] → "No runs reported" (US-1.7). */
	recentRuns?: RecentRun[];
}

export interface CatalogPage {
	total: number;
	matched: number;
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
	const label = `flow ${task.origin.flowId} · step ${task.origin.stepId}`;
	return task.origin.flowExists ? { label, flowId: task.origin.flowId } : { label: 'flow not found', flowId: null, title: label };
}

/** The detail's fields (FR-006), in the order shown; recent runs follow as their own section. */
export const DETAIL_FIELDS = [
	{ key: 'name', label: 'Name' },
	{ key: 'taskId', label: 'ID' },
	{ key: 'namespace', label: 'Namespace' },
	{ key: 'className', label: 'Class' },
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
		items: (w.items ?? []).map(fromWireCatalogTask)
	};
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
}

export const NO_FILTERS: CatalogFilters = { q: '', namespace: 'all', state: 'all', destructiveOnly: false };

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
	const query = params.toString();
	return query ? `?${query}` : '';
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
	| { name: 'pending'; suspended: boolean }
	| { name: 'error'; message: string };

export type SuspendActionEvent =
	| { type: 'send'; suspended: boolean }
	| { type: 'ok'; task: CatalogTaskView }
	| { type: 'fail'; error: ApiError };

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
		case 'send':
			return state.name === 'pending' ? { state, reread: [] } : { state: { name: 'pending', suspended: event.suspended }, reread: [] };
		case 'ok':
			return { state: { name: 'idle' }, task: event.task, reread: ['list'] };
		case 'fail':
			return { state: { name: 'error', message: refusalText(event.error) }, reread: ['item', 'list'] };
	}
}
