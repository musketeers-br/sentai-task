// Spec 023 User Story 3 (data-model §6): what the Overview points at, above spec 019's cards — the
// unread summary, Needs attention and the next 24 hours. Pure: it reads spec 019's AreaCardView
// and the catalog page and never redefines them. Every item comes from a read that succeeded; a
// read that did not is named, never turned into an empty list or a zero (FR-026, FR-029).
import type { CatalogPage, CatalogTaskView } from '$lib/catalog/catalog';
import { refusalLine, type AreaCardView } from './overview';

export type AttentionAction = { label: string; query: string } | { label: string; disabledReason: string };

export interface AttentionItem {
	id: 'backup' | 'suspended' | 'unclassified';
	text: string;
	detail: string;
	action: AttentionAction;
}

export interface AttentionView {
	items: AttentionItem[];
	/** What this band could not read; "Nothing needs attention" only when this is empty too. */
	missing: string[];
}

export interface AttentionInput {
	/** Spec 019's cards, or null when the summary itself was not read. */
	cards: AreaCardView[] | null;
	/** The unfiltered catalog read, or null when it was not read. */
	catalog: CatalogPage | null;
	/** A step type of category `backup` is declared (none is, today). */
	backupStepDeclared: boolean;
}

export function attention(input: AttentionInput): AttentionView {
	const items: AttentionItem[] = [];
	const missing: string[] = [];

	if (input.cards === null) missing.push('Instance summary');
	else {
		const activity = input.cards.find((c) => c.area === 'activity');
		if (!activity || activity.state.kind !== 'ok') missing.push('Activity');
		else {
			const lastBackup = String(activity.state.headline.lastBackup ?? '');
			if (lastBackup === '' || lastBackup.toLowerCase() === 'never') {
				items.push({
					id: 'backup',
					text: 'No backup has ever been taken on this instance',
					detail: `last backup: ${lastBackup || 'Never'} · uptime ${String(activity.state.headline.uptime ?? '—')}`,
					action: input.backupStepDeclared
						? { label: 'Add a backup step', query: '?view=flows' }
						: { label: 'Add a backup step', disabledReason: 'no backup step type is declared' }
				});
			}
		}
	}

	if (input.catalog === null) missing.push('Task catalog');
	else {
		const page = input.catalog;
		const counts = page.counts.kind === 'value' ? page.counts.value : null;
		const suspendedTasks = page.items.filter((t) => t.suspended.kind === 'value' && t.suspended.value);
		const suspended = counts ? counts.suspended : suspendedTasks.length;
		if (suspended > 0) {
			items.push({
				id: 'suspended',
				text: suspended === 1 ? '1 scheduled task is suspended' : `${suspended} scheduled tasks are suspended`,
				detail: suspendedTasks.map((t) => t.name).join(' · '),
				action: { label: 'Show in catalog', query: '?view=catalog&filter=suspended' }
			});
		}
		const unclassified = counts ? counts.unclassified : page.items.filter((t) => t.destructive === 'unknown').length;
		if (unclassified > 0) {
			items.push({
				id: 'unclassified',
				text: `${unclassified} of ${page.total} tasks have no destructiveness classification`,
				detail: 'an unclassified task cannot get the confirmation gate',
				action: { label: 'Show them', query: '?view=catalog&unclassifiedOnly=1' }
			});
		}
	}

	return { items, missing };
}

export interface ScheduleSlot {
	/** "HH:MM", the half hour the tasks fall in, on the instance clock. */
	start: string;
	count: number;
	destructive: number;
	suspended: number;
}

export interface ScheduleStrip {
	slots: ScheduleSlot[];
	total: number;
	destructive: number;
	suspended: number;
	flowScheduled: boolean;
	/** The first next run after the window, as the platform wrote it (to the minute), or null. */
	nextAfter: string | null;
}

export type StripResult = { kind: 'ready'; strip: ScheduleStrip } | { kind: 'unread'; why: string };

const STAMP = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/;
const HALF_HOUR = 30 * 60 * 1000;
const DAY = 24 * 60 * 60 * 1000;

/** A platform timestamp as a number on its own clock (no timezone is applied or assumed). */
function stamp(text: string): number | null {
	const m = STAMP.exec(text);
	return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) : null;
}

const hhmm = (ms: number) => new Date(ms).toISOString().slice(11, 16);

/**
 * Spec 023 FR-023: the next 24 hours by half hour. `now` is the instance's clock — the summary's
 * readAt — because next runs are written on that clock; the browser's clock may be elsewhere.
 */
export function scheduleStrip(items: CatalogTaskView[], now: string | null): StripResult {
	const start = now === null ? null : stamp(now);
	if (start === null) return { kind: 'unread', why: 'needs the instance clock, which comes with the summary' };
	const end = start + DAY;

	const slots = new Map<number, ScheduleSlot>();
	let total = 0;
	let destructive = 0;
	let suspended = 0;
	let nextAfter: { at: number; text: string } | null = null;

	for (const t of items) {
		if (t.nextRun.kind !== 'value') continue;
		const at = stamp(t.nextRun.value);
		if (at === null || at < start) continue;
		if (at >= end) {
			if (nextAfter === null || at < nextAfter.at) nextAfter = { at, text: t.nextRun.value.slice(0, 16) };
			continue;
		}
		const key = Math.floor(at / HALF_HOUR) * HALF_HOUR;
		const slot = slots.get(key) ?? { start: hhmm(key), count: 0, destructive: 0, suspended: 0 };
		const isDestructive = t.destructive === 'yes';
		const isSuspended = t.suspended.kind === 'value' && t.suspended.value;
		slot.count++;
		if (isDestructive) slot.destructive++;
		if (isSuspended) slot.suspended++;
		slots.set(key, slot);
		total++;
		if (isDestructive) destructive++;
		if (isSuspended) suspended++;
	}

	return {
		kind: 'ready',
		strip: {
			slots: [...slots.entries()].sort(([a], [b]) => a - b).map(([, s]) => s),
			total,
			destructive,
			suspended,
			flowScheduled: items.some((t) => t.origin && !(t.suspended.kind === 'value' && t.suspended.value)),
			nextAfter: nextAfter?.text ?? null
		}
	};
}

export interface UnreadReading {
	what: string;
	/** The platform's status and words, verbatim. */
	line: string;
}

/**
 * Spec 023 FR-029: every reading the Overview could not make — the summary as a whole, each
 * refused or unreachable card, and the catalog — so none is found only by scanning.
 */
export function unreadSummary(input: { cards: AreaCardView[] | null; summary: string | null; catalog: string | null }): UnreadReading[] {
	const unread: UnreadReading[] = [];
	if (input.summary !== null) unread.push({ what: 'Instance summary', line: input.summary });
	for (const card of input.cards ?? []) {
		if (card.state.kind !== 'ok') unread.push({ what: card.label, line: refusalLine(card.state) });
	}
	if (input.catalog !== null) unread.push({ what: 'Task catalog', line: input.catalog });
	return unread;
}
