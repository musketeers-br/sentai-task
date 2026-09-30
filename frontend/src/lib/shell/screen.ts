// Which screen the single prerendered page shows. The static file server has no SPA fallback,
// so the screen travels in the query string, like `flow` and `run` (spec 007 research R-1).
// Spec 019 (clarification Q1): an address that names no screen, flow or run opens *Overview*;
// every older address keeps its meaning (a `flow` or `run` without `view` is the flow editor).
export type Screen = 'overview' | 'flows' | 'catalog' | 'targets' | 'runs';

const NAMED: readonly string[] = ['overview', 'flows', 'catalog', 'targets', 'runs'];

export function screenOf(url: URL): Screen {
	const view = url.searchParams.get('view');
	if (view !== null && NAMED.includes(view)) return view as Screen;
	if (url.searchParams.has('flow') || url.searchParams.has('run')) return 'flows';
	return 'overview';
}

/** The same address showing `screen`; `flow`/`run` are kept so Flows reopens what was open. */
export function urlForScreen(url: URL, screen: Screen): URL {
	const next = new URL(url);
	next.searchParams.set('view', screen);
	next.searchParams.delete('area');
	return next;
}

/** Spec 019: *Overview*, showing the detail view of `area` (null: the cards). */
export function urlForArea(url: URL, area: string | null): URL {
	const next = urlForScreen(url, 'overview');
	if (area !== null) next.searchParams.set('area', area);
	return next;
}
