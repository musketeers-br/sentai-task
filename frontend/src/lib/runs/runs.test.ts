import { describe, expect, it } from 'vitest';
import {
	countsLine,
	emptyText,
	fromWireRunSummary,
	mergePage,
	nextCursor,
	pageParams,
	queryFromUrl,
	urlForQuery,
	urlForRun,
	type RunSummaryView
} from './runs';

// The shape of GET /runs items (spec 012 contracts/api-delta.md).
const wire = {
	guid: 'G1',
	flowId: '8',
	flowRevision: 2,
	state: 'failed',
	startedAt: '2026-09-29 10:00:00',
	finishedAt: '2026-09-29 10:01:00',
	dispatchedBy: '_SYSTEM',
	seq: 41,
	flowName: 'Nightly checks',
	totalDurationMs: 60000,
	stepCounts: { queued: 0, running: 0, paused: 0, completed: 3, failed: 1, cancelled: 0 }
};

const summary = (seq: number): RunSummaryView => ({ ...fromWireRunSummary(wire), seq, guid: `G${seq}` });

describe('queryFromUrl / urlForQuery', () => {
	it('round-trips flow and state through the address, dropping an open run', () => {
		const url = new URL('http://h/csp/sentai/?view=runs&flow=3&runsFlow=8&runsState=failed&run=X&from=runs');
		const q = queryFromUrl(url);
		expect(q).toEqual({ flow: '8', state: 'failed' });
		const back = urlForQuery(url, q);
		expect(back.searchParams.get('view')).toBe('runs');
		expect(back.searchParams.get('runsFlow')).toBe('8');
		expect(back.searchParams.get('runsState')).toBe('failed');
		expect(back.searchParams.get('run')).toBeNull();
		// The editor's open flow is not a filter and is left alone.
		expect(back.searchParams.get('flow')).toBe('3');
	});

	it('ignores an unknown state and an out-of-range page size', () => {
		expect(queryFromUrl(new URL('http://h/?runsState=bogus&pageSize=500'))).toEqual({});
		expect(queryFromUrl(new URL('http://h/?pageSize=2'))).toEqual({ pageSize: 2 });
	});
});

describe('urlForRun', () => {
	it('opens the run with its flow and remembers it came from the Runs screen, filters kept', () => {
		const url = urlForRun(new URL('http://h/?view=runs&runsFlow=8&flow=3'), { guid: 'G', flowId: '8' });
		expect(url.searchParams.get('view')).toBeNull();
		expect(url.searchParams.get('flow')).toBe('8');
		expect(url.searchParams.get('run')).toBe('G');
		expect(url.searchParams.get('from')).toBe('runs');
		expect(url.searchParams.get('runsFlow')).toBe('8');
	});
});

describe('pageParams', () => {
	it('builds the GET /runs query', () => {
		expect(pageParams({ flow: '8', state: 'completed' }, null)).toBe('flowId=8&state=completed&limit=50');
		expect(pageParams({ pageSize: 2 }, 40)).toBe('limit=2&before=40');
	});
});

describe('fromWireRunSummary', () => {
	it('reads every summary field', () => {
		const s = fromWireRunSummary(wire);
		expect(s).toMatchObject({ seq: 41, flowName: 'Nightly checks', state: 'failed', totalDurationMs: 60000 });
		expect(s.stepCounts.failed).toBe(1);
	});
});

describe('paging', () => {
	it('mergePage appends without duplicates (FR-008)', () => {
		const merged = mergePage([summary(9), summary(8)], [summary(8), summary(7)]);
		expect(merged.map((r) => r.seq)).toEqual([9, 8, 7]);
	});

	it('nextCursor is the last seq of a full page, null after a short one', () => {
		expect(nextCursor([summary(9), summary(8)], 2)).toBe(8);
		expect(nextCursor([summary(9)], 2)).toBeNull();
		expect(nextCursor([], 2)).toBeNull();
	});
});

describe('texts', () => {
	it('counts line', () => {
		expect(countsLine(fromWireRunSummary(wire).stepCounts)).toBe('3 completed · 1 failed');
		expect(countsLine({ queued: 1, running: 1, paused: 0, completed: 0, failed: 0, cancelled: 2 })).toBe(
			'0 completed · 0 failed · 2 cancelled · 2 not finished'
		);
	});

	it('empty states', () => {
		expect(emptyText({ flow: '8' })).toBe('No runs for this flow yet.');
		expect(emptyText({})).toBe('No runs yet. Run a flow and it appears here.');
	});
});
