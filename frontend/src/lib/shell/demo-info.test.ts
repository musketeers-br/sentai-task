import { describe, expect, it, vi } from 'vitest';
import { loadDemoInfo, parseDemoInfo } from './demo-info';

// Spec 011 US3 (data-model §2): the public demo's sign-in hint. Anything but a well-formed file
// means "not a demo", and the sign-in screen shows nothing extra.
const valid = { account: 'sentai-demo', password: 'sentai-demo-2026', showcase: 'Showcase: nightly checks across servers' };

describe('parseDemoInfo', () => {
	it('accepts the three fields', () => {
		expect(parseDemoInfo(valid)).toEqual(valid);
	});

	it('refuses a missing or empty field', () => {
		expect(parseDemoInfo({ ...valid, showcase: undefined })).toBeNull();
		expect(parseDemoInfo({ ...valid, account: '' })).toBeNull();
	});

	it('refuses wrong types and non-objects', () => {
		expect(parseDemoInfo({ ...valid, password: 42 })).toBeNull();
		expect(parseDemoInfo('sentai-demo')).toBeNull();
		expect(parseDemoInfo(null)).toBeNull();
		expect(parseDemoInfo([valid])).toBeNull();
	});

	it('refuses oversize values (at most 199 characters each)', () => {
		expect(parseDemoInfo({ ...valid, showcase: 'x'.repeat(200) })).toBeNull();
		expect(parseDemoInfo({ ...valid, showcase: 'x'.repeat(199) })).not.toBeNull();
	});
});

describe('loadDemoInfo', () => {
	it('reads demo.json beside the page', async () => {
		const fetchFn = vi.fn(async () => new Response(JSON.stringify(valid), { status: 200 }));
		expect(await loadDemoInfo(fetchFn)).toEqual(valid);
		expect(fetchFn).toHaveBeenCalledWith('/csp/sentai/demo.json', expect.objectContaining({ cache: 'no-store' }));
	});

	it('maps 404, non-JSON and network failures to null', async () => {
		expect(await loadDemoInfo(async () => new Response('Not found', { status: 404 }))).toBeNull();
		expect(await loadDemoInfo(async () => new Response('<html>', { status: 200 }))).toBeNull();
		expect(await loadDemoInfo(async () => { throw new TypeError('offline'); })).toBeNull();
	});
});
