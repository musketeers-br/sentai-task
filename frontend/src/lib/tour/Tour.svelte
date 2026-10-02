<script lang="ts">
	import { wrapTab } from '$lib/shell/dialog-focus';
	import { pad, placeCard, unionRect, type Point, type Rect, type Size } from './anchor';
	import { tour } from './tour.svelte';

	// Spec 021 (plan D-2/D-4, data-model §4): the coach-mark overlay. One full-viewport native
	// <dialog> — the page behind is inert (no accidental drags mid-tour), Escape fires `cancel`,
	// and the veil is an SVG evenodd path whose hole is the anchor region; the spotlight ring
	// carries the geometry the e2e asserts (contracts/tour.md §2). Nothing is stored (FR-010).

	let dialogEl: HTMLDialogElement;
	let cardEl: HTMLElement | undefined = $state();
	let returnFocus: Element | null = null;

	let viewport = $state<Size>({ width: 0, height: 0 });
	let hole = $state<Rect | null>(null);
	let card = $state<Point>({ x: 12, y: 12 });

	const mark = $derived(tour.steps[tour.step - 1]);
	const last = $derived(tour.step === tour.steps.length);
	/** The spotlight hole grows 8 px past its anchor on every side (data-model §3). */
	const HOLE_PAD = 8;

	function rectOf(el: Element): Rect {
		const b = el.getBoundingClientRect();
		return { x: b.left, y: b.top, width: b.width, height: b.height };
	}

	/** Spotlight and card position, recomputed on open, on step change and on window resize. */
	function recompute(): void {
		const size: Size = { width: window.innerWidth, height: window.innerHeight };
		const found = mark.anchor
			.map((selector) => document.querySelector(selector))
			.filter((el): el is Element => el !== null)
			.map(rectOf);
		const anchor = unionRect(found);
		// A selector that no longer matches: the mark still speaks, centered, without a
		// spotlight — a value, never a throw (Constitution IV, data-model §3).
		const holeNext = anchor === null ? null : pad(anchor, HOLE_PAD);
		const cardSize: Size = { width: cardEl?.offsetWidth ?? 0, height: cardEl?.offsetHeight ?? 0 };
		// The state writes come last and nothing here reads what it writes: the effect that
		// calls this stays a plain dependency-driven effect (a self-referencing one is fenced
		// by the runtime after its first run, which froze the spotlight on mark 1).
		viewport = size;
		hole = holeNext;
		card =
			holeNext === null
				? {
						x: Math.max(12, (size.width - cardSize.width) / 2),
						y: Math.max(12, (size.height - cardSize.height) / 2)
					}
				: placeCard(holeNext, size, cardSize);
	}

	/** The SVG veil: the whole viewport minus the rounded spotlight hole. */
	const veilPath = $derived.by(() => {
		const { width: w, height: h } = viewport;
		if (w === 0 || h === 0) return '';
		const rounded = hole === null ? '' : ` ${roundedRect(hole, 8)}`;
		return `M0 0 H${w} V${h} H0 Z${rounded}`;
	});

	function roundedRect(rect: Rect, r: number): string {
		const { x, y, width: w, height: h } = rect;
		return `M${x + r} ${y} H${x + w - r} A${r} ${r} 0 0 1 ${x + w} ${y + r} V${y + h - r} A${r} ${r} 0 0 1 ${x + w - r} ${y + h} H${x + r} A${r} ${r} 0 0 1 ${x} ${y + h - r} V${y + r} A${r} ${r} 0 0 1 ${x + r} ${y} Z`;
	}

	// The single open/close path, as in Modal.svelte: the state drives the dialog, never the
	// other way round. Escape is intercepted so it means skip (FR-006) and still closes via here.
	$effect(() => {
		if (tour.open && !dialogEl.open) {
			returnFocus = document.activeElement;
			dialogEl.showModal();
		} else if (!tour.open && dialogEl.open) {
			dialogEl.close();
		}
	});

	$effect(() => {
		if (!tour.open) return;
		const step = tour.step; // recompute per mark, and once on open
		void step;
		recompute();
	});

	$effect(() => {
		if (!tour.open) return;
		const onResize = () => recompute();
		window.addEventListener('resize', onResize);
		return () => window.removeEventListener('resize', onResize);
	});

	function oncancel(event: Event) {
		event.preventDefault(); // FR-006: Escape means skip; the effect above is the only closer
		tour.skip();
	}

	function onclose() {
		if (returnFocus instanceof HTMLElement && returnFocus.isConnected) returnFocus.focus();
		returnFocus = null;
	}

	function onkeydown(event: KeyboardEvent) {
		wrapTab(dialogEl, event);
	}
</script>

<dialog
	bind:this={dialogEl}
	class="tour"
	aria-modal="true"
	aria-labelledby="tour-title"
	aria-describedby="tour-mark-body"
	{oncancel}
	{onclose}
	{onkeydown}
>
	{#if tour.open}
		<svg class="veil" width={viewport.width} height={viewport.height} viewBox={`0 0 ${viewport.width} ${viewport.height}`} aria-hidden="true">
			<path fill-rule="evenodd" d={veilPath} />
			{#if hole}
				<rect
					data-testid="tour-spotlight"
					x={hole.x}
					y={hole.y}
					width={hole.width}
					height={hole.height}
					rx="8"
					fill="none"
					stroke="var(--color-border)"
					stroke-width="1.5"
				/>
			{/if}
		</svg>
		<div class="card" bind:this={cardEl} style:left={`${card.x}px`} style:top={`${card.y}px`}>
			<!-- svelte-ignore a11y_autofocus -->
			<h2 id="tour-title" tabindex="-1" autofocus>Tour</h2>
			<p class="indicator" aria-live="polite" data-testid="tour-indicator">{tour.step} of {tour.steps.length}</p>
			<p class="body" id="tour-mark-body" data-testid="tour-mark-body">{mark.body}</p>
			<div class="actions">
				<button type="button" class="quiet" onclick={() => tour.skip()}>Skip</button>
				<span class="spacer"></span>
				{#if last}
					<button type="button" class="primary" onclick={() => tour.finish()}>Done</button>
				{:else}
					<button type="button" class="primary" onclick={() => tour.next()}>Next</button>
				{/if}
			</div>
		</div>
	{/if}
</dialog>

<style>
	.tour {
		position: fixed;
		inset: 0;
		width: 100%;
		height: 100%;
		max-width: none;
		max-height: none;
		margin: 0;
		padding: 0;
		border: none;
		background: transparent;
		color: var(--color-text);
	}

	.tour::backdrop {
		background: transparent;
	}

	.veil {
		position: absolute;
		inset: 0;
		display: block;
	}

	.veil path {
		fill: color-mix(in srgb, var(--color-ground) 70%, transparent);
	}

	.card {
		position: absolute;
		display: flex;
		flex-direction: column;
		gap: 8px;
		width: max-content;
		max-width: 360px;
		padding: 16px 18px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: var(--color-card-shadow);
	}

	.card h2 {
		margin: 0;
		font-size: var(--size-bodyStrong);
		font-weight: 600;
		outline: none;
	}

	.indicator {
		margin: 0;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.body {
		margin: 0;
		font-size: var(--size-body);
		line-height: 1.5;
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-top: 4px;
	}

	.spacer {
		flex-grow: 1;
	}

	.actions button {
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 7px 14px;
		cursor: pointer;
	}

	.actions .primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
	}

	.actions .quiet {
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
	}
</style>
