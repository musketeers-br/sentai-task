// Spec 014 data-model §1: one caption per scene, in English. Injected by the recorder into its own
// browser session only; the product never shows them.
export const CAPTIONS = {
	flow: 'A maintenance flow: checks on two servers, one join',
	validate: 'Validated against the live instance',
	run: 'Run now: the platform authorizes every call',
	parallel: '3 checks in parallel, 2 servers',
	join: 'Join: all must succeed, then the report',
	result: 'Every step keeps its result',
	log: 'The run tells its own story',
	history: 'History of every run',
	targets: 'Servers it can reach'
} as const;

export type Scene = keyof typeof CAPTIONS;

/** Script for page.addInitScript: a caption box that `window.__caption(text)` updates. */
export const CAPTION_INIT = `(() => {
	window.__caption = (text) => {
		let box = document.getElementById('media-caption');
		if (!box) {
			box = document.createElement('div');
			box.id = 'media-caption';
			box.setAttribute('aria-hidden', 'true');
			Object.assign(box.style, {
				position: 'fixed', left: '24px', bottom: '24px', zIndex: '2147483647', maxWidth: '640px',
				padding: '10px 16px', borderRadius: '8px', font: '600 20px/1.3 system-ui, sans-serif',
				color: '#fff', background: 'rgba(12, 14, 20, 0.86)', boxShadow: '0 4px 18px rgba(0,0,0,.35)',
				pointerEvents: 'none'
			});
			document.body.appendChild(box);
		}
		box.textContent = text;
	};
})();`;
