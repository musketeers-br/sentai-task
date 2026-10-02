import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from './client';
import { session } from './session.svelte';

// The race us22-cancel-alert-notice found: the live run view polls every second, and the session
// renews its token proactively. A /refresh revokes the previous access token, so a poll sent just
// before the renewal comes back 401 after the session already holds the new token. That 401 must
// not sign the session out (it used to: the renewed token was wiped and polling froze).

type Call = { url: string; method: string; authorization: string | undefined };
let calls: Call[];
let respond: (call: Call) => Promise<Response>;

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status });
const pair = (n: number) => ({ access_token: `access-${n}`, refresh_token: `refresh-${n}`, sub: '_SYSTEM', iat: 1000, exp: 1060 });
const run = { guid: 'G1', flowId: '1', flowRevision: 1, state: 'running', startedAt: '2026-10-02 09:56:32', finishedAt: '', steps: [] };

beforeEach(async () => {
	calls = [];
	vi.stubGlobal('fetch', async (input: RequestInfo | URL, init: RequestInit = {}) => {
		const headers = (init.headers ?? {}) as Record<string, string>;
		const call = { url: String(input), method: init.method ?? 'GET', authorization: headers.Authorization };
		calls.push(call);
		return respond(call);
	});
	respond = async () => json(200, pair(1));
	await session.login('_SYSTEM', 'SYS');
});

afterEach(() => {
	session.logout();
	vi.unstubAllGlobals();
});

describe('request — a 401 that predates a renewal', () => {
	it('repeats the call once with the renewed token and keeps the session', async () => {
		respond = async (call) => {
			if (call.url.endsWith('/runs/G1') && call.authorization === 'Bearer access-1') {
				// The renewal completes while this request is in flight; then the old token is refused.
				respond = async (inner) => (inner.url.endsWith('/runs/G1') ? json(200, run) : json(200, pair(2)));
				await session.login('_SYSTEM', 'SYS');
				return json(401, {});
			}
			return json(200, run);
		};

		const result = await api.getRun('G1');

		expect(result.ok).toBe(true);
		expect(session.status).toBe('signed-in');
		expect(session.authorization()).toBe('Bearer access-2');
		const polls = calls.filter((c) => c.url.endsWith('/runs/G1')).map((c) => c.authorization);
		expect(polls).toEqual(['Bearer access-1', 'Bearer access-2']);
	});

	it('still expires the session on a 401 for the current token, without repeating the call', async () => {
		respond = async () => json(401, {});

		const result = await api.getRun('G1');

		expect(result).toEqual({ ok: false, error: { kind: 'unauthorized' } });
		expect(session.status).toBe('expired');
		expect(calls.filter((c) => c.url.endsWith('/runs/G1'))).toHaveLength(1);
	});
});
