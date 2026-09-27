// One 60-second JWT pair authenticates every call — SysAdmin and SENTAI.REST.Dispatcher alike
// (spec 002 Clarifications 2026-09-21). Refresh is proactive, before expiry, never a reaction
// to a 401 (FR-034). The access token lives in memory only. Spec 010 US3: the refresh token is
// also kept in this tab's sessionStorage (kept-sign-in.ts), so a reload redeems it instead of
// asking for the password; nothing about permissions is stored or cached (Constitution III) —
// the platform decides on every request.
import { eraseKept, handOver, readKept, reclaim, writeKept, type KeptStorage } from './kept-sign-in';

const ADMIN_BASE = '/api/admin';
const REFRESH_MARGIN_SECONDS = 15;

interface TokenPair {
	access_token: string;
	refresh_token: string;
	sub: string;
	iat: number;
	exp: number;
}

/** `restoring`: a kept sign-in is being redeemed on load (spec 010); no sign-in form yet. */
export type SessionStatus = 'signed-out' | 'restoring' | 'signed-in' | 'expired';
/** How this page's sign-in began: typed with the password, or redeemed from the kept one. */
export type SessionOrigin = 'password' | 'restored';

const ENDED = 'Your session ended — sign in again.';
const COPIED = 'Sign in to continue in this tab.';

/** This tab's sessionStorage, or null where there is none (prerendering) or it is refused. */
function tabStorage(): KeptStorage | null {
	try {
		return typeof sessionStorage === 'undefined' ? null : sessionStorage;
	} catch {
		return null;
	}
}
export type LoginResult = { ok: true } | { ok: false; message: string };

function basicCredentials(user: string, password: string): string {
	const bytes = new TextEncoder().encode(`${user}:${password}`);
	return btoa(String.fromCharCode(...bytes));
}

export class Session {
	status = $state<SessionStatus>('signed-out');
	user = $state<string | null>(null);
	refreshCount = $state(0);
	origin = $state<SessionOrigin | null>(null);
	/** Why the sign-in form is shown after a load: the kept sign-in ended, or this tab is a copy. */
	ended = $state<string | null>(null);

	#storage: () => KeptStorage | null;

	constructor(storage: () => KeptStorage | null = tabStorage) {
		this.#storage = storage;
		// Decided before the first render, so a reload never flashes the sign-in form (SC-003).
		if (readKept(storage()).kind === 'kept') this.status = 'restoring';
	}

	#access: string | null = null;
	#refresh: string | null = null;
	#timer: ReturnType<typeof setTimeout> | undefined;

	async login(user: string, password: string): Promise<LoginResult> {
		let res: Response;
		try {
			res = await fetch(`${ADMIN_BASE}/login`, {
				method: 'POST',
				headers: {
					Authorization: `Basic ${basicCredentials(user, password)}`,
					'Content-Type': 'application/json'
				},
				body: '{}'
			});
		} catch (e) {
			return { ok: false, message: `Could not reach the IRIS instance: ${(e as Error).message}` };
		}
		if (!res.ok) {
			return {
				ok: false,
				message:
					res.status === 401
						? 'The platform rejected these credentials.'
						: `Login failed: HTTP ${res.status} ${res.statusText}`
			};
		}
		this.origin = 'password';
		this.ended = null;
		this.#accept((await res.json()) as TokenPair);
		return { ok: true };
	}

	/**
	 * Spec 010 FR-009/FR-012/FR-013, once per page load: redeem the tab's kept refresh token (the
	 * refresh token alone is accepted — research R-3.1). A copy made by duplicating a live tab is
	 * dropped without a request; any failure to redeem erases it and says the session ended.
	 */
	async restore(): Promise<void> {
		const kept = readKept(this.#storage());
		if (kept.kind === 'copied') {
			eraseKept(this.#storage());
			this.status = 'signed-out';
			this.ended = COPIED;
			return;
		}
		if (kept.kind === 'none') {
			if (this.status === 'restoring') this.status = 'signed-out';
			return;
		}
		this.status = 'restoring';
		let res: Response;
		try {
			res = await fetch(`${ADMIN_BASE}/refresh`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ refresh_token: kept.refreshToken })
			});
		} catch (e) {
			this.#endKept(`${ENDED} Could not reach the IRIS instance: ${(e as Error).message}`);
			return;
		}
		if (!res.ok) {
			this.#endKept(ENDED);
			return;
		}
		this.origin = 'restored';
		this.ended = null;
		this.#accept((await res.json()) as TokenPair);
	}

	/** `pagehide` hands the kept token to the tab's next document; bfcache `pageshow` takes it back. */
	attachPageLifecycle(win: Window): void {
		win.addEventListener('pagehide', () => {
			if (this.status === 'signed-in') handOver(this.#storage());
		});
		win.addEventListener('pageshow', (event) => {
			if ((event as PageTransitionEvent).persisted && this.status === 'signed-in') reclaim(this.#storage());
		});
	}

	logout(): void {
		clearTimeout(this.#timer);
		eraseKept(this.#storage());
		this.#access = null;
		this.#refresh = null;
		this.user = null;
		this.origin = null;
		this.ended = null;
		this.status = 'signed-out';
	}

	/** Called when the platform answers 401 to an authenticated call. */
	expire(): void {
		clearTimeout(this.#timer);
		eraseKept(this.#storage());
		this.#access = null;
		this.status = 'expired';
	}

	#endKept(message: string): void {
		eraseKept(this.#storage());
		this.status = 'signed-out';
		this.ended = message;
	}

	authorization(): string | null {
		return this.#access ? `Bearer ${this.#access}` : null;
	}

	/**
	 * A separate login handed to one dispatched run. `/refresh` revokes the previous access token,
	 * so a run sharing this session's pair died at this session's next proactive refresh (≤ 45 s).
	 * The run gets its own pair instead: the access token authorizes the dispatch and the refresh
	 * token lets the backend renew the run's credential itself (E-1). The password is used for this
	 * one request and never kept.
	 */
	async dedicatedToken(
		password: string
	): Promise<{ ok: true; authorization: string; refreshToken: string } | { ok: false; message: string }> {
		if (!this.user) return { ok: false, message: 'Not signed in.' };
		let res: Response;
		try {
			res = await fetch(`${ADMIN_BASE}/login`, {
				method: 'POST',
				headers: { Authorization: `Basic ${basicCredentials(this.user, password)}`, 'Content-Type': 'application/json' },
				body: '{}'
			});
		} catch (e) {
			return { ok: false, message: `Could not reach the IRIS instance: ${(e as Error).message}` };
		}
		if (!res.ok) {
			return {
				ok: false,
				message: res.status === 401 ? 'The platform rejected this password.' : `Login failed: HTTP ${res.status}`
			};
		}
		const pair = (await res.json()) as TokenPair;
		return { ok: true, authorization: `Bearer ${pair.access_token}`, refreshToken: pair.refresh_token };
	}

	#accept(pair: TokenPair): void {
		this.#access = pair.access_token;
		this.#refresh = pair.refresh_token;
		this.user = pair.sub;
		this.status = 'signed-in';
		writeKept(this.#storage(), pair.refresh_token);
		// exp - iat, not exp - Date.now(): immune to clock skew between browser and IRIS.
		const lifetime = pair.exp - Math.floor(pair.iat);
		const delay = Math.max(5, lifetime - REFRESH_MARGIN_SECONDS) * 1000;
		clearTimeout(this.#timer);
		this.#timer = setTimeout(() => void this.#renew(), delay);
	}

	async #renew(): Promise<void> {
		try {
			const res = await fetch(`${ADMIN_BASE}/refresh`, {
				method: 'POST',
				headers: { Authorization: `Bearer ${this.#access}`, 'Content-Type': 'application/json' },
				body: JSON.stringify({ refresh_token: this.#refresh })
			});
			if (!res.ok) {
				this.expire();
				return;
			}
			this.#accept((await res.json()) as TokenPair);
			this.refreshCount++;
		} catch {
			this.expire();
		}
	}
}

export const session = new Session();
