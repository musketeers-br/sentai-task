// Which screen the single prerendered page shows. The static file server has no SPA fallback,
// so the screen travels in the query string, like `flow` and `run` (spec 007 research R-1).
export type Screen = 'flows' | 'catalog' | 'targets' | 'runs';

export function screenOf(url: URL): Screen {
	const view = url.searchParams.get('view');
	return view === 'catalog' || view === 'targets' || view === 'runs' ? view : 'flows';
}

/** The same address showing `screen`; `flow`/`run` are kept so Flows reopens what was open. */
export function urlForScreen(url: URL, screen: Screen): URL {
	const next = new URL(url);
	if (screen === 'flows') next.searchParams.delete('view');
	else next.searchParams.set('view', screen);
	return next;
}
