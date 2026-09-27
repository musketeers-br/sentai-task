// Which screen the single prerendered page shows. The static file server has no SPA fallback,
// so the screen travels in the query string, like `flow` and `run` (spec 007 research R-1).
export type Screen = 'flows' | 'catalog';

export function screenOf(url: URL): Screen {
	return url.searchParams.get('view') === 'catalog' ? 'catalog' : 'flows';
}

/** The same address showing `screen`; `flow`/`run` are kept so Flows reopens what was open. */
export function urlForScreen(url: URL, screen: Screen): URL {
	const next = new URL(url);
	if (screen === 'catalog') next.searchParams.set('view', 'catalog');
	else next.searchParams.delete('view');
	return next;
}
