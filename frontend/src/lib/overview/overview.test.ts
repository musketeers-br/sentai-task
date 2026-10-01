import { describe, expect, it, vi } from 'vitest';
import {
	canSchedule,
	columnLabel,
	createAutoRefresh,
	fromWireAreaFlow,
	fromWireOnDemand,
	fromWireReading,
	fromWireSummary,
	headlineLines,
	paramFindings,
	refusalLine,
	rowCountLine,
	visibleRows,
	withCardReport,
	withSummary,
	NO_TABLE_STATE,
	type WireAreaEntry,
	type WireSummary
} from './overview';

const ok = (area: string, headline: Record<string, unknown>, group: 'instance' | 'report' = 'instance', stepType: string | null = null): WireAreaEntry => ({
	area,
	group,
	outcome: 'ok',
	readAt: '2026-09-29 21:00:00',
	headline,
	problem: null,
	stepType
});

const SUMMARY: WireSummary = {
	readAt: '2026-09-29 21:00:00',
	areas: [
		ok('processes', { count: 53, busiest: { Pid: 1177, Routine: '%SYS.WorkQueueMgr', Commands: 16719717 } }),
		ok('locks', { count: 36 }),
		ok('memory', { usedPercent: 86.4, mostUsed: { description: 'Security System', usedPercent: 100 } }),
		ok('activity', { uptime: '0d  0h 18m', lastBackup: 'Never', busyProcesses: 2, globalRefsPerSecond: 363811 }),
		ok('devices', { count: 12 }),
		ok('licenses', { inUse: 1, authorized: 8 }),
		ok('web-sessions', { count: 5 }),
		{
			area: 'security',
			group: 'report',
			outcome: 'refused',
			readAt: 't',
			headline: null,
			problem: { title: 'Forbidden', detail: 'HTTP 403: no reason given', httpStatus: 403, platformStatus: { errors: [], summary: '' } },
			stepType: 'security-posture-report'
		},
		ok('web-apps', { count: 26 }, 'report', 'web-app-inventory'),
		ok('alerts', { seriousAlerts: 5, applicationErrors: 0 }, 'report', 'system-alerts-check'),
		{ area: 'secrets', group: 'report', outcome: 'unreachable', readAt: 't', headline: null, problem: { detail: 'PLATFORM_UNREACHABLE: the management API did not answer', httpStatus: 0 }, stepType: 'secrets-inventory' }
	]
};

describe('cards (US1)', () => {
	const cards = fromWireSummary(SUMMARY);

	it('keeps the API order, fixed labels and each outcome', () => {
		expect(cards.map((c) => c.label)).toEqual([
			'Processes',
			'Locks',
			'Shared memory',
			'Activity',
			'Devices',
			'Licenses',
			'Web sessions',
			'Security posture',
			'Web applications',
			'System alerts',
			'Secrets'
		]);
		expect(cards.map((c) => c.state.kind)).toEqual(['ok', 'ok', 'ok', 'ok', 'ok', 'ok', 'ok', 'refused', 'ok', 'ok', 'unreachable']);
	});

	it('keeps a refusal verbatim', () => {
		const sec = cards[7].state;
		expect(sec).toMatchObject({ kind: 'refused', httpStatus: 403, title: 'Forbidden', detail: 'HTTP 403: no reason given', platformStatus: { errors: [], summary: '' } });
		expect(refusalLine(sec)).toBe('HTTP 403 — HTTP 403: no reason given');
		expect(refusalLine(cards[10].state)).toBe('PLATFORM_UNREACHABLE: the management API did not answer');
	});

	it('formats headlines without computing anything', () => {
		expect(cards[0].headlineLines).toEqual(['53 processes', 'Busiest: %SYS.WorkQueueMgr (pid 1,177) · 16,719,717 commands']);
		expect(cards[2].headlineLines).toEqual(['86.4% of shared memory used', 'Most used: Security System 100%']);
		expect(cards[5].headlineLines).toEqual(['1 of 8 license units in use']);
		expect(cards[9].headlineLines).toEqual(['5 serious alerts · 0 application errors']);
		expect(headlineLines('memory', { usedPercent: null, mostUsed: null })).toEqual(['— of shared memory used']);
	});

	it('never labels a host CPU, memory or log on its own (FR-006)', () => {
		const words = cards.flatMap((c) => [c.label, ...c.headlineLines]).join(' | ');
		expect(words).not.toMatch(/\bCPU\b/);
		expect(words).not.toMatch(/(^|\| )Memory\b/);
		expect(words).not.toMatch(/\blogs?\b/i);
	});

	it('offers Schedule this check only where the API maps a step type', () => {
		expect(cards.filter(canSchedule).map((c) => c.area)).toEqual(['security', 'web-apps', 'alerts', 'secrets']);
	});
});

describe('readings (US2)', () => {
	const view = fromWireReading({
		area: 'processes',
		readAt: 't',
		columns: ['Pid', 'Nspace', 'Commands', 'CPUTime'],
		rows: [
			{ Pid: 3, Nspace: 'USER', Commands: 12, CPUTime: null },
			{ Pid: 1, Nspace: 'irisapp', Commands: 1394911, CPUTime: 9000 },
			{ Pid: 2, Nspace: 'IRISAPP', Commands: 0, CPUTime: 340 }
		],
		computed: []
	});

	it('sorts numbers numerically, strings case-insensitively, empty last', () => {
		expect(visibleRows(view, { sortBy: 'Commands', descending: true, filter: '' }).map((r) => r.Pid)).toEqual([1, 3, 2]);
		expect(visibleRows(view, { sortBy: 'Commands', descending: false, filter: '' }).map((r) => r.Pid)).toEqual([2, 3, 1]);
		expect(visibleRows(view, { sortBy: 'CPUTime', descending: true, filter: '' }).map((r) => r.Pid)).toEqual([1, 2, 3]);
		expect(visibleRows(view, { sortBy: 'CPUTime', descending: false, filter: '' }).map((r) => r.Pid)).toEqual([2, 1, 3]);
	});

	it('filters by case-insensitive text over every cell and counts', () => {
		const shown = visibleRows(view, { ...NO_TABLE_STATE, filter: 'irisapp' });
		expect(shown.map((r) => r.Pid)).toEqual([1, 2]);
		expect(rowCountLine(view.rows.length, shown.length)).toBe('3 rows · 2 shown');
		expect(rowCountLine(65, 65)).toBe('65 rows');
		expect(rowCountLine(1, 1)).toBe('1 row');
	});

	it("names the process CPU time as the process's", () => {
		expect(columnLabel('CPUTime')).toBe('CPU time (process)');
		expect(columnLabel('Nspace')).toBe('Nspace');
	});
});

describe('auto-refresh (US2, FR-008)', () => {
	function harness(visible: { value: boolean }) {
		const timers: Array<() => void> = [];
		const read = vi.fn(async () => {});
		const refresh = createAutoRefresh({
			intervalMs: 10000,
			read,
			isVisible: () => visible.value,
			setTimer: (fn) => (timers.push(fn), timers.length),
			clearTimer: (h) => {
				timers[(h as number) - 1] = () => {};
			}
		});
		const fire = async () => {
			const fn = timers.at(-1)!;
			fn();
			await Promise.resolve();
			await Promise.resolve();
		};
		return { refresh, read, fire, timers };
	}

	it('is off by default and reads on each tick when on', async () => {
		const visible = { value: true };
		const h = harness(visible);
		expect(h.refresh.on).toBe(false);
		expect(h.timers.length).toBe(0);
		h.refresh.start();
		await h.fire();
		await h.fire();
		expect(h.read).toHaveBeenCalledTimes(2);
	});

	it('never reads while hidden and resumes when visible', async () => {
		const visible = { value: false };
		const h = harness(visible);
		h.refresh.start();
		await h.fire();
		await h.fire();
		expect(h.read).not.toHaveBeenCalled();
		visible.value = true;
		h.refresh.visibilityChanged();
		await Promise.resolve();
		expect(h.read).toHaveBeenCalledTimes(1);
	});

	it('stops', async () => {
		const h = harness({ value: true });
		h.refresh.start();
		h.refresh.stop();
		expect(h.refresh.on).toBe(false);
		await h.fire();
		expect(h.read).not.toHaveBeenCalled();
	});
});

describe('card reports (US3, clarification Q2)', () => {
	const report = fromWireOnDemand({
		stepType: 'web-app-inventory',
		state: 'completed',
		failureReason: '',
		report: { summary: { high: 2, medium: 3, info: 0 } },
		ranAt: '2026-09-29 21:05:00'
	});

	it('counts by severity', () => {
		expect(report.counts).toEqual({ high: 2, medium: 3, info: 0 });
		expect(fromWireOnDemand({ stepType: 's', state: 'failed', failureReason: 'ERROR #822: Access Denied', report: null, ranAt: 't' })).toMatchObject({
			state: 'failed',
			failureReason: 'ERROR #822: Access Denied',
			counts: { high: 0, medium: 0, info: 0 }
		});
	});

	it('is kept on its card across Refresh and only there', () => {
		const cards = withCardReport(fromWireSummary(SUMMARY), 'web-apps', report);
		expect(cards.filter((c) => c.report !== null).map((c) => c.area)).toEqual(['web-apps']);
		const refreshed = withSummary(cards, fromWireSummary(SUMMARY));
		expect(refreshed.find((c) => c.area === 'web-apps')!.report).toBe(report);
	});

	it('maps PARAM_* errors to the form findings', () => {
		const findings = [{ stepId: 'ondemand', code: 'PARAM_OUT_OF_RANGE', parameter: 'maxSeriousAlerts', message: 'must be at least 0' }];
		expect(paramFindings({ errors: findings, warnings: [] })).toEqual(findings);
	});
});

describe('schedule this check (US4)', () => {
	it('reads the new flow id and whether validation blocks the dialog', () => {
		expect(fromWireAreaFlow({ flow: { id: 457 }, validation: { errors: [], warnings: [] } })).toEqual({ flowId: '457', hasErrors: false });
		expect(fromWireAreaFlow({ flow: { id: '9' }, validation: { errors: [{ stepId: '01', code: 'CATEGORY_NOT_FOUND', message: 'x' }], warnings: [] } }).hasErrors).toBe(true);
	});
});
