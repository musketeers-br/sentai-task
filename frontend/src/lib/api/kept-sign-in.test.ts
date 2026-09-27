import { describe, expect, it } from 'vitest';
import { eraseKept, handOver, KEPT_KEY, readKept, reclaim, writeKept, type KeptStorage } from './kept-sign-in';

// spec 010 US3 (research R-3, data-model §5): the tab's kept sign-in — one refresh token and a
// `live` handover flag in sessionStorage, nothing else (FR-011).

function fakeStorage(initial: Record<string, string> = {}): KeptStorage & { data: Map<string, string> } {
	const data = new Map(Object.entries(initial));
	return {
		data,
		getItem: (k) => data.get(k) ?? null,
		setItem: (k, v) => void data.set(k, v),
		removeItem: (k) => void data.delete(k)
	};
}

const throwing: KeptStorage = {
	getItem: () => {
		throw new Error('SecurityError');
	},
	setItem: () => {
		throw new Error('QuotaExceededError');
	},
	removeItem: () => {
		throw new Error('SecurityError');
	}
};

const record = (value: unknown) => ({ [KEPT_KEY]: JSON.stringify(value) });

describe('readKept', () => {
	it('is none when nothing is kept', () => {
		expect(readKept(fakeStorage())).toEqual({ kind: 'none' });
	});

	it('is none, and erases, when the record is corrupt, of another version or has no token', () => {
		for (const bad of [{ [KEPT_KEY]: '{not json' }, record({ v: 2, refreshToken: 't', live: false }), record({ v: 1, live: false })]) {
			const storage = fakeStorage(bad);
			expect(readKept(storage)).toEqual({ kind: 'none' });
			expect(storage.data.has(KEPT_KEY)).toBe(false);
		}
	});

	it('is copied while another live page owns the token (a duplicated tab)', () => {
		expect(readKept(fakeStorage(record({ v: 1, refreshToken: 't', live: true })))).toEqual({ kind: 'copied' });
	});

	it('is kept after a handover (a reload or a restored tab)', () => {
		expect(readKept(fakeStorage(record({ v: 1, refreshToken: 't', live: false })))).toEqual({ kind: 'kept', refreshToken: 't' });
	});

	it('never throws when storage refuses access', () => {
		expect(readKept(throwing)).toEqual({ kind: 'none' });
		expect(() => writeKept(throwing, 't')).not.toThrow();
		expect(() => handOver(throwing)).not.toThrow();
		expect(() => reclaim(throwing)).not.toThrow();
		expect(() => eraseKept(throwing)).not.toThrow();
	});
});

describe('writeKept (FR-011)', () => {
	it('stores exactly the version, the refresh token and the live flag', () => {
		const storage = fakeStorage();
		writeKept(storage, 'refresh-1');
		const stored = JSON.parse(storage.data.get(KEPT_KEY)!);
		expect(Object.keys(stored).sort()).toEqual(['live', 'refreshToken', 'v']);
		expect(stored).toEqual({ v: 1, refreshToken: 'refresh-1', live: true });
		expect([...storage.data.keys()]).toEqual([KEPT_KEY]);
		for (const forbidden of ['access', 'access_token', 'sub', 'user', 'role', 'roles', 'permission', 'password']) {
			expect(stored).not.toHaveProperty(forbidden);
		}
	});
});

describe('handover', () => {
	it('pagehide hands the token to the next load; pageshow from bfcache takes it back', () => {
		const storage = fakeStorage();
		writeKept(storage, 'refresh-1');
		handOver(storage);
		expect(JSON.parse(storage.data.get(KEPT_KEY)!)).toEqual({ v: 1, refreshToken: 'refresh-1', live: false });
		reclaim(storage);
		expect(JSON.parse(storage.data.get(KEPT_KEY)!)).toEqual({ v: 1, refreshToken: 'refresh-1', live: true });
	});

	it('handover and reclaim do nothing when nothing is kept', () => {
		const storage = fakeStorage();
		handOver(storage);
		reclaim(storage);
		expect(storage.data.size).toBe(0);
	});

	it('eraseKept removes the record', () => {
		const storage = fakeStorage(record({ v: 1, refreshToken: 't', live: true }));
		eraseKept(storage);
		expect(storage.data.size).toBe(0);
	});
});
