import { describe, expect, it } from 'vitest';
import type { ApiError } from '$lib/api/client';
import {
	catalogQuery,
	createSequence,
	DETAIL_FIELDS,
	originMark,
	reduceSuspendAction,
	suspendActionFor,
	fromWireCatalogPage,
	namespaceOptions,
	fromWireCatalogTask,
	orderByNextRun,
	refusalText,
	statusLabel,
	type CatalogTaskView,
	type WireCatalogTask
} from './catalog';

// Items copied from specs/006-task-catalog-api/contracts/api-delta.md.
const task4: WireCatalogTask = {
	taskId: 4, name: 'Integrity Check', namespace: '%SYS',
	class: '%SYS.Task.IntegrityCheck', runAsUser: '_SYSTEM', timePeriod: 'Weekly',
	nextRun: '2026-09-28 02:00:00', lastStarted: '', lastFinished: '',
	status: '1', lastError: '', suspended: true,
	destructive: false, destructiveUnknown: false,
	isDestructive: false, lastRun: ''
};

const task1000: WireCatalogTask = {
	taskId: 1000, name: 'SentaiTask: 1#01', namespace: 'IRISAPP',
	class: 'sentai.dispatch.ScheduledFlowTask', runAsUser: '_SYSTEM', timePeriod: 'Daily',
	nextRun: '2026-09-27 00:00:00', lastStarted: '2026-09-26 00:00:01',
	lastFinished: '2026-09-26 00:00:01', status: '1', lastError: 'Success',
	suspended: false, destructive: false, destructiveUnknown: false,
	isDestructive: false, lastRun: '2026-09-26 00:00:01',
	origin: { flowId: '1', stepId: '01', flowExists: true }
};

const task1003: WireCatalogTask = {
	taskId: 1003, name: '…', namespace: 'IRISAPP', class: '…', runAsUser: '…',
	timePeriod: 'Daily', destructive: false, destructiveUnknown: true,
	unavailable: [
		{
			read: 'info',
			fields: ['nextRun', 'lastStarted', 'lastFinished', 'status', 'lastError', 'suspended'],
			httpStatus: 404,
			platformStatus: {
				errors: [{ error: "ERROR #5809: Object to Load not found, class '%SYS.Task', ID '1003'" }],
				summary: 'ERROR #5809: Object to Load not found, class &#39;%SYS.Task&#39;, ID &#39;1003&#39;'
			}
		}
	]
};

describe('fromWireCatalogTask', () => {
	it('maps every field of a fully read task as a value', () => {
		expect(fromWireCatalogTask(task4)).toEqual({
			taskId: 4,
			name: 'Integrity Check',
			namespace: '%SYS',
			className: { kind: 'value', value: '%SYS.Task.IntegrityCheck' },
			runAsUser: { kind: 'value', value: '_SYSTEM' },
			timePeriod: { kind: 'value', value: 'Weekly' },
			nextRun: { kind: 'value', value: '2026-09-28 02:00:00' },
			lastStarted: { kind: 'value', value: '' },
			lastFinished: { kind: 'value', value: '' },
			status: { kind: 'value', value: '1' },
			lastError: { kind: 'value', value: '' },
			suspended: { kind: 'value', value: true },
			destructive: 'no'
		});
	});

	it('marks the fields of a failed read unavailable, with the platform reason', () => {
		const view = fromWireCatalogTask(task1003);
		const reason = { read: 'info', httpStatus: 404, text: "ERROR #5809: Object to Load not found, class '%SYS.Task', ID '1003'" };
		for (const field of ['nextRun', 'lastStarted', 'lastFinished', 'status', 'lastError', 'suspended'] as const) {
			expect(view[field], field).toEqual({ kind: 'unavailable', reason });
		}
		expect(view.className).toEqual({ kind: 'value', value: '…' });
	});

	it('gives "no reason given" when the platform stated none', () => {
		const view = fromWireCatalogTask({
			taskId: 7, name: 'x', namespace: '%SYS',
			unavailable: [{ read: 'single', fields: ['class', 'runAsUser', 'timePeriod'], httpStatus: 403, platformStatus: { errors: [], summary: '' } }]
		});
		expect(view.className).toEqual({ kind: 'unavailable', reason: { read: 'single', httpStatus: 403, text: 'no reason given' } });
	});

	it('keeps a field the API did not send absent, never empty', () => {
		const view = fromWireCatalogTask({ taskId: 8, name: 'x', namespace: '%SYS' });
		expect(view.runAsUser).toEqual({ kind: 'absent' });
		expect(view.nextRun).toEqual({ kind: 'absent' });
		expect(view.suspended).toEqual({ kind: 'absent' });
	});

	it('reads destructiveness as yes, no or unknown', () => {
		expect(fromWireCatalogTask({ ...task4, destructive: true }).destructive).toBe('yes');
		expect(fromWireCatalogTask(task4).destructive).toBe('no');
		expect(fromWireCatalogTask(task1003).destructive).toBe('unknown');
	});

	it('never reads the deprecated isDestructive and lastRun aliases', () => {
		const { lastFinished: _, ...rest } = task1000;
		const view = fromWireCatalogTask({ ...rest, isDestructive: true, lastRun: '2026-09-26 00:00:01' });
		expect(view.destructive).toBe('no');
		expect(view.lastFinished).toEqual({ kind: 'absent' });
	});

	it('reads the class only from `class`, never from the old `className`', () => {
		const view = fromWireCatalogTask({ taskId: 9, name: 'x', namespace: '%SYS', className: 'System' });
		expect(view.className).toEqual({ kind: 'absent' });
		expect(fromWireCatalogPage({ total: '16', matched: '2', items: [task4, task1000] })).toMatchObject({
			total: 16,
			matched: 2,
			items: [{ taskId: 4 }, { taskId: 1000 }]
		});
	});
});

describe('orderByNextRun', () => {
	const at = (taskId: number, name: string, nextRun?: string): CatalogTaskView =>
		fromWireCatalogTask({ taskId, name, namespace: '%SYS', ...(nextRun === undefined ? {} : { nextRun }) });
	const ids = (list: CatalogTaskView[]) => list.map((t) => t.taskId);

	it('orders timestamps ascending', () => {
		expect(ids(orderByNextRun([at(1, 'a', '2026-09-28 02:00:00'), at(2, 'b', '2026-09-27 00:00:00'), at(3, 'c', '2026-09-28 00:30:00')]))).toEqual([2, 3, 1]);
	});

	it('puts other text after timestamps, then "", then absent', () => {
		expect(ids(orderByNextRun([at(1, 'a'), at(2, 'b', ''), at(3, 'c', 'Runs After #1:00'), at(4, 'd', '2026-09-28 00:00:00')]))).toEqual([4, 3, 2, 1]);
	});

	it('breaks ties by name, then task id', () => {
		expect(ids(orderByNextRun([at(3, 'b', ''), at(2, 'a', ''), at(1, 'b', '')]))).toEqual([2, 1, 3]);
	});

	it('never changes a value or the input list', () => {
		const input = [at(1, 'a', 'Runs After #1:00'), at(2, 'b', '2026-09-27 00:00:00')];
		const copy = structuredClone(input);
		const out = orderByNextRun(input);
		expect(input).toEqual(copy);
		expect(out[1]).toBe(input[0]);
		expect(out[1].nextRun).toEqual({ kind: 'value', value: 'Runs After #1:00' });
	});
});

describe('refusalText and statusLabel', () => {
	const problem = (detail: string, platformStatus?: { errors: Array<{ error: string }>; summary: string }): ApiError => ({
		kind: 'problem', status: 403, title: 'Forbidden', detail, platformStatus
	});

	it('uses the detail when there is one', () => {
		expect(refusalText({ kind: 'problem', status: 502, title: 'Bad Gateway', detail: 'PLATFORM_UNREACHABLE: x' })).toBe(
			'HTTP 502 — PLATFORM_UNREACHABLE: x'
		);
	});

	it('otherwise joins the platform errors', () => {
		expect(refusalText(problem('', { errors: [{ error: 'ERROR #1' }, { error: 'ERROR #2' }], summary: 'x' }))).toBe(
			'HTTP 403 — ERROR #1; ERROR #2'
		);
	});

	it('otherwise says "no reason given"', () => {
		expect(refusalText(problem('', { errors: [], summary: '' }))).toBe('HTTP 403 — no reason given');
		expect(refusalText(problem(''))).toBe('HTTP 403 — no reason given');
	});

	it('labels status "1" as OK (1) and shows any other status verbatim', () => {
		expect(statusLabel('1')).toBe('OK (1)');
		expect(statusLabel('-1')).toBe('-1');
		expect(statusLabel('ERROR #5001: x')).toBe('ERROR #5001: x');
	});
});

describe('filters (US-3)', () => {
	it('offers "all" plus the distinct namespaces of an unfiltered page, as returned', () => {
		const page = fromWireCatalogPage({
			total: 4, matched: 4,
			items: [task4, task1000, { ...task4, taskId: 5, namespace: 'USER' }, { ...task1000, taskId: 1001 }]
		});
		expect(namespaceOptions(page)).toEqual(['all', '%SYS', 'IRISAPP', 'USER']);
	});

	it('sends only the filters that differ from their default', () => {
		const defaults = { q: '', namespace: 'all', state: 'all', destructiveOnly: false } as const;
		expect(catalogQuery(defaults)).toBe('');
		expect(catalogQuery({ ...defaults, q: '  ' })).toBe('');
		expect(catalogQuery({ q: 'SentaiTask: 1#', namespace: '%SYS', state: 'suspended', destructiveOnly: true })).toBe(
			'?q=SentaiTask%3A+1%23&namespace=%25SYS&filter=suspended&destructiveOnly=1'
		);
		expect(catalogQuery({ ...defaults, state: 'scheduled' })).toBe('?filter=scheduled');
	});

	it('lets only the latest request apply, whatever order the answers arrive in', () => {
		const sequence = createSequence();
		const first = sequence.next();
		const second = sequence.next();
		expect(sequence.isLatest(second)).toBe(true);
		expect(sequence.isLatest(first)).toBe(false);
	});
});

describe('detail (US-1.4-7, US-2)', () => {
	it('marks a SentaiTask task with its flow and step, linking only when the flow exists', () => {
		expect(originMark(fromWireCatalogTask(task1000))).toEqual({ label: 'flow 1 · step 01', flowId: '1' });
		expect(
			originMark(fromWireCatalogTask({ ...task1000, origin: { flowId: '1', stepId: '01', flowExists: false } }))
		).toEqual({ label: 'flow not found', flowId: null, title: 'flow 1 · step 01' });
		// No origin in the API, no mark: whatever the name says.
		const { origin: _, ...unmarked } = task1000;
		expect(originMark(fromWireCatalogTask(unmarked))).toBeNull();
	});

	it('keeps recent runs absent, empty or verbatim, with no computed duration', () => {
		expect(fromWireCatalogTask(task4).recentRuns).toBeUndefined();
		expect(fromWireCatalogTask({ ...task4, recentRuns: [] }).recentRuns).toEqual([]);
		const row = { LastStart: '2026-09-26 00:00:00', Completed: '2026-09-26 00:00:00', Status: '1', Result: 'Success', Username: '_SYSTEM', LogDatetime: '2026-09-26 00:00:01' };
		expect(fromWireCatalogTask({ ...task4, recentRuns: [row] }).recentRuns).toEqual([
			{ start: '2026-09-26 00:00:00', completed: '2026-09-26 00:00:00', status: '1', result: 'Success', user: '_SYSTEM', loggedAt: '2026-09-26 00:00:01' }
		]);
	});

	it('shows exactly the FR-006 fields, in order', () => {
		expect(DETAIL_FIELDS.map((f) => f.label)).toEqual([
			'Name', 'ID', 'Namespace', 'Class', 'Run as user', 'Time period', 'Next run', 'Last started',
			'Last finished', 'Status', 'Last error', 'Suspended', 'Destructiveness', 'Origin'
		]);
	});
});

describe('suspend / resume action (US-4)', () => {
	it('goes idle → pending (disabled) → idle, taking the task from the answer and re-reading the list', () => {
		const task = fromWireCatalogTask(task1000);
		expect(suspendActionFor(task)).toBe('suspend');
		const pending = reduceSuspendAction({ name: 'idle' }, { type: 'send', suspended: true });
		expect(pending).toEqual({ state: { name: 'pending', suspended: true }, reread: [] });
		const answered = fromWireCatalogTask({ ...task1000, suspended: true });
		expect(reduceSuspendAction(pending.state, { type: 'ok', task: answered })).toEqual({
			state: { name: 'idle' },
			task: answered,
			reread: ['list']
		});
		expect(suspendActionFor(answered)).toBe('resume');
	});

	it('shows a refusal verbatim and re-reads item and list; offers nothing when suspended is unavailable', () => {
		const pending = reduceSuspendAction({ name: 'idle' }, { type: 'send', suspended: false }).state;
		const error: ApiError = { kind: 'problem', status: 403, title: 'Forbidden', detail: '', platformStatus: { errors: [], summary: '' } };
		expect(reduceSuspendAction(pending, { type: 'fail', error })).toEqual({
			state: { name: 'error', message: 'HTTP 403 — no reason given' },
			reread: ['item', 'list']
		});
		expect(suspendActionFor(fromWireCatalogTask(task1003))).toBeNull();
	});
});
