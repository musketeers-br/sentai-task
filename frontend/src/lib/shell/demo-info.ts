// Spec 011 US3 (plan D-13, data-model §2): the public demo writes `demo.json` beside the page with
// the published demo account and the showcase flow's name. A normal installation ships a neutral
// `{"demo": false}` (static/demo.json; a 404 would log a console error on every sign-in screen),
// and anything malformed counts as "not a demo" — the sign-in screen then shows nothing extra.
// Data only: nothing in it is evaluated or trusted beyond being displayed.
export interface DemoInfo {
	account: string;
	password: string;
	showcase: string;
}

const MAX = 200;
const DEMO_URL = '/csp/sentai/demo.json';

const text = (v: unknown): v is string => typeof v === 'string' && v.length > 0 && v.length < MAX;

export function parseDemoInfo(value: unknown): DemoInfo | null {
	if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
	const { account, password, showcase } = value as Record<string, unknown>;
	return text(account) && text(password) && text(showcase) ? { account, password, showcase } : null;
}

/** The edge: one read, any failure is "not a demo". `fetchFn` is injected for tests. */
export async function loadDemoInfo(fetchFn: typeof fetch = fetch): Promise<DemoInfo | null> {
	try {
		const res = await fetchFn(DEMO_URL, { cache: 'no-store' });
		if (!res.ok) return null;
		return parseDemoInfo(await res.json());
	} catch {
		return null;
	}
}
