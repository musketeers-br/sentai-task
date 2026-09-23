// One 60-second JWT pair authenticates every call — SysAdmin and SENTAI.REST.Dispatcher alike
// (spec 002 Clarifications 2026-09-21). Refresh is proactive, before expiry, never a reaction
// to a 401 (FR-034). Tokens live in memory only; nothing about permissions is cached
// (Constitution III) — the platform decides on every request.

const ADMIN_BASE = '/api/admin';
const REFRESH_MARGIN_SECONDS = 15;

interface TokenPair {
	access_token: string;
	refresh_token: string;
	sub: string;
	iat: number;
	exp: number;
}

export type SessionStatus = 'signed-out' | 'signed-in' | 'expired';
export type LoginResult = { ok: true } | { ok: false; message: string };

function basicCredentials(user: string, password: string): string {
	const bytes = new TextEncoder().encode(`${user}:${password}`);
	return btoa(String.fromCharCode(...bytes));
}

class Session {
	status = $state<SessionStatus>('signed-out');
	user = $state<string | null>(null);
	refreshCount = $state(0);

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
		this.#accept((await res.json()) as TokenPair);
		return { ok: true };
	}

	logout(): void {
		clearTimeout(this.#timer);
		this.#access = null;
		this.#refresh = null;
		this.user = null;
		this.status = 'signed-out';
	}

	/** Called when the platform answers 401 to an authenticated call. */
	expire(): void {
		clearTimeout(this.#timer);
		this.#access = null;
		this.status = 'expired';
	}

	authorization(): string | null {
		return this.#access ? `Bearer ${this.#access}` : null;
	}

	#accept(pair: TokenPair): void {
		this.#access = pair.access_token;
		this.#refresh = pair.refresh_token;
		this.user = pair.sub;
		this.status = 'signed-in';
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
