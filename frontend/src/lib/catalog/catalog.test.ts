import { describe, expect, it } from 'vitest';
import type { ApiError } from '$lib/api/client';
import {
	fromWireCatalogPage,
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
