import { describe, expect, it } from 'vitest';
import { screenOf, urlForArea, urlForScreen } from './screen';

const at = (query: string) => new URL(`http://h/csp/sentai/index.html${query}`);

describe('screenOf (spec 019 Q1)', () => {
	it('opens Overview when the address names nothing', () => {
		expect(screenOf(at(''))).toBe('overview');
		expect(screenOf(at('?view=nope'))).toBe('overview');
	});

	it('keeps every older address meaningful', () => {
		expect(screenOf(at('?flow=1'))).toBe('flows');
		expect(screenOf(at('?run=g'))).toBe('flows');
		expect(screenOf(at('?flow=1&run=g&from=runs'))).toBe('flows');
		expect(screenOf(at('?view=flows'))).toBe('flows');
		expect(screenOf(at('?view=catalog&task=3'))).toBe('catalog');
		expect(screenOf(at('?view=targets'))).toBe('targets');
		expect(screenOf(at('?view=runs'))).toBe('runs');
		expect(screenOf(at('?view=overview&area=locks'))).toBe('overview');
	});
});

describe('urlForScreen / urlForArea', () => {
	it('writes view=flows explicitly and keeps the open flow', () => {
		const next = urlForScreen(at('?view=overview&area=locks&flow=7'), 'flows');
		expect(next.searchParams.get('view')).toBe('flows');
		expect(next.searchParams.get('flow')).toBe('7');
		expect(next.searchParams.has('area')).toBe(false);
		expect(screenOf(next)).toBe('flows');
	});

	it('drops the area when going back to the cards', () => {
		expect(urlForScreen(at('?view=overview&area=locks'), 'overview').searchParams.has('area')).toBe(false);
	});

	it('addresses a detail view', () => {
		const next = urlForArea(at('?view=runs&runsState=failed'), 'processes');
		expect(next.searchParams.get('view')).toBe('overview');
		expect(next.searchParams.get('area')).toBe('processes');
		expect(urlForArea(next, null).searchParams.has('area')).toBe(false);
	});
});
