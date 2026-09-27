import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { KEPT_KEY, type KeptStorage } from './kept-sign-in';
import { Session } from './session.svelte';

// spec 010 US3 (research R-3.4, data-model §5): redeem the kept refresh token on load; the
// "session ended" path; a copied tab never replays its copy; erase on sign-out and rejection.

const ENDED = 'Your session ended — sign in again.';

function fakeStorage(initial: Record<string, string> = {}): KeptStorage & { data: Map<string, string> } {
	const data = new Map(Object.entries(initial));
	return {
		data,
		getItem: (k) => data.get(k) ?? null,
		setItem: (k, v) => void data.set(k, v),
		removeItem: (k) => void data.delete(k)
	};
}

const kept = (live: boolean, refreshToken = 'kept-refresh') => ({ [KEPT_KEY]: JSON.stringify({ v: 1, refreshToken, live }) });
const stored = (s: ReturnType<typeof fakeStorage>) => (s.data.has(KEPT_KEY) ? JSON.parse(s.data.get(KEPT_KEY)!) : null);

type Call = { url: string; method: string; headers: Record<string, string>; body: unknown };
let calls: Call[];
let respond: (call: Call) => Response | Promise<Response>;

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status });
const pair = (n: number) => ({ access_token: `access-${n}`, refresh_token: `refresh-${n}`, sub: '_SYSTEM', iat: 1000, exp: 1060 });

beforeEach(() => {
	calls = [];
	vi.stubGlobal('fetch', async (input: RequestInfo | URL, init: RequestInit = {}) => {
		const call = {
			url: String(input),
			method: init.method ?? 'GET',
			headers: { ...(init.headers as Record<string, string>) },
			body: init.body ? JSON.parse(String(init.body)) : undefined
		};
		calls.push(call);
		return respond(call);
	});
});

afterEach(() => {
	vi.useRealTimers();
	vi.unstubAllGlobals();
});

describe('Session.restore', () => {
	it('redeems the kept refresh token alone and keeps the new one', async () => {
		const storage = fakeStorage(kept(false));
		const session = new Session(() => storage);
		expect(session.status).toBe('restoring'); // no sign-in form flashes before the redeem (SC-003)
		respond = () => json(200, pair(2));

		await session.restore();

		expect(calls).toHaveLength(1);
		expect(calls[0].url).toBe('/api/admin/refresh');
		expect(calls[0].method).toBe('POST');
		expect(calls[0].body).toEqual({ refresh_token: 'kept-refresh' });
		expect(calls[0].headers).not.toHaveProperty('Authorization');
		expect(session.status).toBe('signed-in');
		expect(session.origin).toBe('restored');
		expect(session.user).toBe('_SYSTEM');
		expect(session.authorization()).toBe('Bearer access-2');
		expect(stored(storage)).toEqual({ v: 1, refreshToken: 'refresh-2', live: true });
		session.logout();
	});

	it('shows "session ended" and erases the record when the platform refuses (expired, revoked, restarted)', async () => {
		const storage = fakeStorage(kept(false));
		const session = new Session(() => storage);
		respond = () => json(401, {});
		await session.restore();
		expect(session.status).toBe('signed-out');
		expect(session.ended).toBe(ENDED);
		expect(stored(storage)).toBeNull();
	});

	it('does the same when the instance cannot be reached, adding the reason', async () => {
		const storage = fakeStorage(kept(false));
		const session = new Session(() => storage);
		respond = () => {
			throw new TypeError('Failed to fetch');
		};
		await session.restore();
		expect(session.status).toBe('signed-out');
		expect(session.ended).toBe(`${ENDED} Could not reach the IRIS instance: Failed to fetch`);
		expect(stored(storage)).toBeNull();
	});

	it('a copied tab never replays the copy: no request, record erased, its own sign-in asked (FR-013)', async () => {
		const storage = fakeStorage(kept(true));
		const session = new Session(() => storage);
		expect(session.status).toBe('signed-out');
		await session.restore();
		expect(calls).toEqual([]);
		expect(stored(storage)).toBeNull();
		expect(session.status).toBe('signed-out');
		expect(session.ended).toBe('Sign in to continue in this tab.');
	});

	it('with nothing kept, asks nothing and says nothing', async () => {
		const storage = fakeStorage();
		const session = new Session(() => storage);
		await session.restore();
		expect(calls).toEqual([]);
		expect(session.status).toBe('signed-out');
		expect(session.ended).toBeNull();
	});

	it('works without storage at all (private windows, prerendering)', async () => {
		const session = new Session(() => null);
		await session.restore();
		expect(session.status).toBe('signed-out');
		respond = () => json(200, pair(1));
		expect(await session.login('_SYSTEM', 'pw')).toEqual({ ok: true });
		session.logout();
	});
});

describe('Session keeps and erases the record', () => {
	it('a password sign-in keeps the token (origin "password"); each proactive renewal rewrites it', async () => {
		vi.useFakeTimers();
		const storage = fakeStorage();
		const session = new Session(() => storage);
		let n = 0;
		respond = () => json(200, pair(++n));
		expect(await session.login('_SYSTEM', 'pw')).toEqual({ ok: true });
		expect(session.origin).toBe('password');
		expect(session.ended).toBeNull();
		expect(stored(storage)).toEqual({ v: 1, refreshToken: 'refresh-1', live: true });

		await vi.advanceTimersByTimeAsync(46_000); // 60 s token, renewed 15 s early (spec 002 FR-034)
		expect(calls.at(-1)!.url).toBe('/api/admin/refresh');
		expect(stored(storage)).toEqual({ v: 1, refreshToken: 'refresh-2', live: true });
		session.logout();
	});

	it('sign-out, a 401 on a call and a failed renewal all erase it', async () => {
		vi.useFakeTimers();
		for (const end of ['logout', 'expire', 'renewal'] as const) {
			const storage = fakeStorage();
			const session = new Session(() => storage);
			respond = () => json(200, pair(1));
			await session.login('_SYSTEM', 'pw');
			expect(stored(storage)).not.toBeNull();
			if (end === 'logout') session.logout();
			if (end === 'expire') session.expire();
			if (end === 'renewal') {
				respond = () => json(401, {});
				await vi.advanceTimersByTimeAsync(46_000);
				expect(session.status).toBe('expired');
			}
			expect(stored(storage), end).toBeNull();
			session.logout();
		}
	});

	it('the run\'s dedicated sign-in is never kept (FR-014)', async () => {
		const storage = fakeStorage();
		const session = new Session(() => storage);
		respond = () => json(200, pair(1));
		await session.login('_SYSTEM', 'pw');
		respond = () => json(200, pair(9));
		const run = await session.dedicatedToken('pw');
		expect(run.ok).toBe(true);
		expect(stored(storage).refreshToken).toBe('refresh-1');
		session.logout();
	});

	it('pagehide hands over; pageshow from bfcache takes back (research R-3.3)', async () => {
		const storage = fakeStorage();
		const session = new Session(() => storage);
		respond = () => json(200, pair(1));
		await session.login('_SYSTEM', 'pw');
		const win = new EventTarget();
		session.attachPageLifecycle(win as unknown as Window);
		win.dispatchEvent(Object.assign(new Event('pagehide'), { persisted: true }));
		expect(stored(storage).live).toBe(false);
		win.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: true }));
		expect(stored(storage).live).toBe(true);
		win.dispatchEvent(Object.assign(new Event('pageshow'), { persisted: false }));
		expect(stored(storage).live).toBe(true);
		session.logout();
	});
});
