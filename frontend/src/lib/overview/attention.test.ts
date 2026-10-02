import { describe, expect, it } from 'vitest';
import { fromWireCatalogPage, type WireCatalogTask } from '$lib/catalog/catalog';
import { attention, scheduleStrip, unreadSummary } from './attention';
import { fromWireSummary, type WireAreaEntry } from './overview';

/**
 * Spec 023 T034 (data-model §6, FR-022, FR-023, FR-026, FR-029). Written before `attention.ts`
 * existed (Principle V). Spec 019's summary cards and the catalog page are read, never redefined;
 * the 24-hour window runs on the instance's clock (the summary's readAt), never the browser's.
 */

const NOW = '2026-10-02 08:18:35';

function entry(area: string, over: Partial<WireAreaEntry> = {}): WireAreaEntry {
	return { area, group: 'instance', outcome: 'ok', readAt: NOW, headline: {}, problem: null, stepType: null, ...over };
}

const activity = (lastBackup: string) => entry('activity', { headline: { uptime: '0d  8h 12m', lastBackup, busyProcesses: 1, globalRefsPerSecond: 720 } });

function task(id: number, name: string, over: Partial<WireCatalogTask> = {}): WireCatalogTask {
	return { taskId: id, name, namespace: '%SYS', class: '%SYS.Task.X', suspended: false, destructive: false, destructiveUnknown: false, nextRun: '', ...over };
}

const ITEMS: WireCatalogTask[] = [
	task(1, 'Security Scan', { nextRun: '2026-10-03 00:00:00', destructiveUnknown: true }),
	task(2, 'Switch Journal', { nextRun: '2026-10-03 00:00:00' }),
	task(3, 'Purge Journal', { nextRun: '2026-10-03 00:30:00', destructiveUnknown: true }),
	task(4, 'Purge Tasks', { nextRun: '2026-10-03 01:00:00', destructive: true }),
	task(5, 'Automatic Table Statistic Collection', { nextRun: '2026-10-03 02:00:00', suspended: true, destructiveUnknown: true }),
	task(6, 'Integrity Check', { nextRun: '2026-10-05 02:00:00', suspended: true }),
	task(7, 'Diagnostic Report', { nextRun: '', destructiveUnknown: true }),
	task(8, 'Already ran today', { nextRun: '2026-10-02 06:00:00' })
];

/** `counts: null` stands for an older API that sends none. */
const page = (items = ITEMS, counts: { suspended: number; destructive: number; unclassified: number } | null = { suspended: 2, destructive: 1, unclassified: 4 }) =>
	fromWireCatalogPage({ total: items.length, matched: items.length, items, ...(counts ? { counts } : {}) });

describe('attention — items only from what was read (FR-022)', () => {
	it('lists the backup, the suspended tasks and the unclassified ones, each with one action', () => {
		const view = attention({ cards: fromWireSummary({ readAt: NOW, areas: [activity('Never')] }), catalog: page(), backupStepDeclared: false });
		expect(view.missing).toEqual([]);
		expect(view.items.map((i) => i.id)).toEqual(['backup', 'suspended', 'unclassified']);

		const [backup, suspended, unclassified] = view.items;
		expect(backup.text).toBe('No backup has ever been taken on this instance');
		expect(backup.detail).toBe('last backup: Never · uptime 0d  8h 12m');
		expect(backup.action).toEqual({ label: 'Add a backup step', disabledReason: 'no backup step type is declared' });

		expect(suspended.text).toBe('2 scheduled tasks are suspended');
		expect(suspended.detail).toBe('Automatic Table Statistic Collection · Integrity Check');
		expect(suspended.action).toEqual({ label: 'Show in catalog', query: '?view=catalog&filter=suspended' });

		expect(unclassified.text).toBe('4 of 8 tasks have no destructiveness classification');
		expect(unclassified.detail).toBe('an unclassified task cannot get the confirmation gate');
		expect(unclassified.action).toEqual({ label: 'Show them', query: '?view=catalog&unclassifiedOnly=1' });
	});

	it('offers the backup action once a backup step type is declared, and says nothing when a backup exists', () => {
		const cards = fromWireSummary({ readAt: NOW, areas: [activity('')] });
		expect(attention({ cards, catalog: page(), backupStepDeclared: true }).items[0].action).toEqual({ label: 'Add a backup step', query: '?view=flows' });
		const backedUp = fromWireSummary({ readAt: NOW, areas: [activity('2026-10-01 23:00:00')] });
		expect(attention({ cards: backedUp, catalog: page(), backupStepDeclared: false }).items.map((i) => i.id)).toEqual(['suspended', 'unclassified']);
	});

	it('uses the singular for one suspended task and counts from the items when an older API sends no counts', () => {
		const one = [task(5, 'Automatic Table Statistic Collection', { suspended: true }), task(2, 'Switch Journal', { destructiveUnknown: true })];
		const view = attention({ cards: fromWireSummary({ readAt: NOW, areas: [activity('x')] }), catalog: page(one, null), backupStepDeclared: false });
		expect(view.items[0].text).toBe('1 scheduled task is suspended');
		expect(view.items[1].text).toBe('1 of 2 tasks have no destructiveness classification');
	});

	it('says what it could not read instead of an empty list', () => {
		const refusedActivity = fromWireSummary({
			readAt: NOW,
			areas: [entry('activity', { outcome: 'refused', headline: null, problem: { httpStatus: 403, detail: 'ERROR #822: Access Denied' } })]
		});
		const view = attention({ cards: refusedActivity, catalog: null, backupStepDeclared: false });
		expect(view.items).toEqual([]);
		expect(view.missing).toEqual(['Activity', 'Task catalog']);
		expect(attention({ cards: null, catalog: page(), backupStepDeclared: false }).missing).toEqual(['Instance summary']);
	});

	it('is empty and complete only when both reads succeeded and nothing needs attention', () => {
		const calm = [task(2, 'Switch Journal')];
		const view = attention({ cards: fromWireSummary({ readAt: NOW, areas: [activity('2026-10-01')] }), catalog: page(calm, { suspended: 0, destructive: 0, unclassified: 0 }), backupStepDeclared: false });
		expect(view).toEqual({ items: [], missing: [] });
	});
});

describe('scheduleStrip — the next 24 hours on the instance clock (FR-023)', () => {
	it('buckets by half hour, marks destructive and suspended, and names what comes after', () => {
		const strip = scheduleStrip(page().items, NOW);
		expect(strip).toEqual({
			kind: 'ready',
			strip: {
				slots: [
					{ start: '00:00', count: 2, destructive: 0, suspended: 0 },
					{ start: '00:30', count: 1, destructive: 0, suspended: 0 },
					{ start: '01:00', count: 1, destructive: 1, suspended: 0 },
					{ start: '02:00', count: 1, destructive: 0, suspended: 1 }
				],
				total: 5,
				destructive: 1,
				suspended: 1,
				flowScheduled: false,
				nextAfter: '2026-10-05 02:00'
			}
		});
	});

	it('floors to the half hour and says whether a SentaiTask flow is scheduled', () => {
		const items = page([task(9, 'SentaiTask: 12 Nightly', { nextRun: '2026-10-02 23:47:00', origin: { flowId: '12', flowExists: true } })]).items;
		const strip = scheduleStrip(items, NOW);
		expect(strip.kind === 'ready' && strip.strip.slots).toEqual([{ start: '23:30', count: 1, destructive: 0, suspended: 0 }]);
		expect(strip.kind === 'ready' && strip.strip.flowScheduled).toBe(true);
		expect(strip.kind === 'ready' && strip.strip.nextAfter).toBeNull();
	});

	it('cannot place anything without the instance clock', () => {
		expect(scheduleStrip(page().items, null)).toEqual({ kind: 'unread', why: 'needs the instance clock, which comes with the summary' });
	});

	it('is empty, not missing, when nothing is scheduled in the window', () => {
		const strip = scheduleStrip(page([task(6, 'Integrity Check', { nextRun: '2026-10-05 02:00:00' })]).items, NOW);
		expect(strip).toEqual({ kind: 'ready', strip: { slots: [], total: 0, destructive: 0, suspended: 0, flowScheduled: false, nextAfter: '2026-10-05 02:00' } });
	});
});

describe('unreadSummary — every reading not made, named (FR-029)', () => {
	it('lists the summary, each refused or unreachable card, and the catalog, verbatim', () => {
		const cards = fromWireSummary({
			readAt: NOW,
			areas: [
				activity('Never'),
				entry('locks', { outcome: 'refused', headline: null, problem: { httpStatus: 403, detail: 'ERROR #822: Access Denied' } }),
				entry('devices', { outcome: 'unreachable', headline: null, problem: { detail: 'connection refused' } })
			]
		});
		expect(unreadSummary({ cards, summary: null, catalog: 'HTTP 403 — no reason given' })).toEqual([
			{ what: 'Locks', line: 'HTTP 403 — ERROR #822: Access Denied' },
			{ what: 'Devices', line: 'connection refused' },
			{ what: 'Task catalog', line: 'HTTP 403 — no reason given' }
		]);
	});

	it('names the whole summary when it could not be read, and is empty when everything was', () => {
		expect(unreadSummary({ cards: null, summary: 'HTTP 500 — boom', catalog: null })).toEqual([{ what: 'Instance summary', line: 'HTTP 500 — boom' }]);
		expect(unreadSummary({ cards: fromWireSummary({ readAt: NOW, areas: [activity('x')] }), summary: null, catalog: null })).toEqual([]);
	});
});
