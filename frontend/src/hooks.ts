import type { Reroute } from '@sveltejs/kit';

// IRIS ServeFiles only answers the explicit file (…/csp/sentai/index.html); resolve that URL
// to the root route instead of the client router's 404.
export const reroute: Reroute = ({ url }) => {
	if (url.pathname.endsWith('/index.html')) return url.pathname.slice(0, -'index.html'.length);
};
