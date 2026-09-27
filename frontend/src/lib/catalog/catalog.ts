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
	origin?: { flowId: string; stepId: string; flowExists: boolean };
	unavailable?: WireUnavailable[];
	className?: string;
	isDestructive?: boolean;
	lastRun?: string;
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
		destructive: w.destructiveUnknown || w.destructive === undefined ? 'unknown' : w.destructive ? 'yes' : 'no'
	};
}

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
