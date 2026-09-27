// Spec 010 US3 (research R-3, data-model §5): the tab's kept sign-in. One refresh token and a
// `live` flag in sessionStorage — per tab, gone when the tab closes. Nothing else is ever stored:
// no access token, user, role or permission (FR-011, Constitution III). Every access is caught,
// so a storage that refuses (private windows, blocked site data) just means "nothing kept".
//
// `live` is the handover between documents of the same tab: true while a page owns the token,
// false after `pagehide`. A load that finds `live: true` is a duplicated tab whose original is
// still using that token; replaying it would make the platform revoke the original's sign-in.

export const KEPT_KEY = 'sentai.signin';

export type KeptStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
export type Kept = { kind: 'none' } | { kind: 'copied' } | { kind: 'kept'; refreshToken: string };

interface KeptRecord {
	v: 1;
	refreshToken: string;
	live: boolean;
}

function read(storage: KeptStorage | null): KeptRecord | null {
	if (!storage) return null;
	let raw: string | null;
	try {
		raw = storage.getItem(KEPT_KEY);
	} catch {
		return null;
	}
	if (raw === null) return null;
	try {
		const record = JSON.parse(raw) as Partial<KeptRecord>;
		if (record.v === 1 && typeof record.refreshToken === 'string' && record.refreshToken !== '' && typeof record.live === 'boolean') {
			return { v: 1, refreshToken: record.refreshToken, live: record.live };
		}
	} catch {
		// Unreadable: treated as absent and removed below.
	}
	eraseKept(storage);
	return null;
}

function write(storage: KeptStorage | null, record: KeptRecord): void {
	try {
		storage?.setItem(KEPT_KEY, JSON.stringify({ v: record.v, refreshToken: record.refreshToken, live: record.live }));
	} catch {
		// Not kept: the next reload asks for the sign-in, as before spec 010.
	}
}

export function readKept(storage: KeptStorage | null): Kept {
	const record = read(storage);
	if (!record) return { kind: 'none' };
	return record.live ? { kind: 'copied' } : { kind: 'kept', refreshToken: record.refreshToken };
}

/** After a sign-in and after every renewal: this page owns the (new) token. */
export function writeKept(storage: KeptStorage | null, refreshToken: string): void {
	write(storage, { v: 1, refreshToken, live: true });
}

/** `pagehide`: the next document of this tab may redeem the token. */
export function handOver(storage: KeptStorage | null): void {
	const record = read(storage);
	if (record) write(storage, { ...record, live: false });
}

/** `pageshow` from the back/forward cache: this page owns the token again. */
export function reclaim(storage: KeptStorage | null): void {
	const record = read(storage);
	if (record) write(storage, { ...record, live: true });
}

export function eraseKept(storage: KeptStorage | null): void {
	try {
		storage?.removeItem(KEPT_KEY);
	} catch {
		// Nothing to erase that we could reach.
	}
}
