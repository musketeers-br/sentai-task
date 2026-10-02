<script lang="ts">
	import { api } from '$lib/api/client';
	import { STEP_TYPE_MIME } from '$lib/canvas/dnd';
	import { createSequence } from '$lib/catalog/catalog';
	import { typeLabel, type StepTypeInfo } from '$lib/flow/document';
	import { collapseSections, paletteSections, type StepSearchOutcome } from '$lib/palette/search';

	let { registry, onadd }: { registry: StepTypeInfo[]; onadd: (type: string) => void } = $props();

	let query = $state('');
	let outcome = $state<StepSearchOutcome | null>(null);

	// Latest-wins for the debounced search request only; the filtering itself stays synchronous.
	const sequence = createSequence();

	/** Spec 023 FR-013: categories the operator opened with "Show N more" (component-local). */
	let expanded = $state<Set<string>>(new Set());
	const UNSUPPORTED = 'unsupported';

	const view = $derived(
		// Spec 011: the filtering logic left the component — this widens a category group with
		// the one group the ranking adds (contracts/palette-search.md). Spec 023: long groups
		// collapse and unsupported types gather at the end, except while searching.
		collapseSections(paletteSections(registry, query, outcome), { expanded, searching: query.trim() !== '' })
	);
	const groups = $derived(
		view.groups.map((g) => ({ category: g.id, suggested: g.id === 'suggested', types: g.shown, total: g.total, hidden: g.hidden }))
	);

	function expand(id: string) {
		expanded = new Set([...expanded, id]);
	}

	// Spec 011 input timing: the same effect-debounce as CatalogScreen's search box — the cleanup
	// clears the previous timer, so only the final keystroke within 150 ms asks (R-012). The
	// local filter above still narrows on every keystroke, so the list is useful before any
	// request is made.
	$effect(() => {
		const text = query;
		if (!text.trim()) {
			outcome = null; // never ask with an empty q (FR-005)
			return;
		}
		const timer = setTimeout(async () => {
			const ticket = sequence.next();
			const result = await api.searchStepTypes(text.trim());
			// A slow response for an old keystroke is discarded, never applied (FR-002). There is
			// no abort of an in-flight request — a superseded response is simply not used.
			if (!sequence.isLatest(ticket)) return;
			// A failed request never reaches the palette as a failure: a transport failure, a 5xx
			// and an unparseable body all collapse to the same degraded state, and none of them
			// can masquerade as "no results" (FR-023, FR-025).
			outcome = result.ok ? result.value : { available: false, reason: 'unreachable' };
		}, 150);
		return () => clearTimeout(timer);
	});

	function ondragstart(event: DragEvent, type: string) {
		event.dataTransfer?.setData(STEP_TYPE_MIME, type);
		if (event.dataTransfer) event.dataTransfer.effectAllowed = 'copy';
	}
</script>

{#snippet stepEntry(t: StepTypeInfo, suggested: boolean)}
	<!-- Spec 004 D-1: unavailable types stay listed (saved flows still use them) but
	     cannot be placed, because the target platform cannot run them in v1. -->
	<button
		type="button"
		class="entry"
		class:unavailable={!t.available}
		disabled={!t.available}
		draggable={t.available ? 'true' : 'false'}
		style:--entry-category={`var(--category-${t.category})`}
		data-step-type={t.type}
		data-suggested={suggested ? 'true' : undefined}
		title={t.available
			? 'Drag onto the canvas, or press Enter to add'
			: 'Not supported on the target platform in v1'}
		ondragstart={(e) => ondragstart(e, t.type)}
		onclick={() => onadd(t.type)}
	>
		<span class="entry-text">
			<span class="entry-name">{typeLabel(t)}</span>
			<span class="entry-class">{#if t.className}{#each t.className.split('.') as part, i (i)}{#if i > 0}.<wbr />{/if}{part}{/each}{:else}subclass of %SYS.Task.Definition{/if}</span>
			{#if !t.available}<span class="entry-unavailable">not supported in v1</span>{/if}
		</span>
		{#if t.destructive}
			<span class="hazard-swatch" title="Destructive step" aria-label="Destructive step"></span>
		{/if}
	</button>
{/snippet}

<aside class="palette" aria-label="Step types">
	<div class="head">
		<h2 class="label">STEP TYPES</h2>
		<label for="palette-search" class="visually-hidden">Search step type</label>
		<input
			id="palette-search"
			type="search"
			placeholder="Search (integrity, purge, journal…)"
			bind:value={query}
		/>
	</div>

	<div class="groups">
		{#each groups as group (group.category)}
			<section class="group" aria-labelledby={`cat-${group.category}`}>
				<h3 class="group-title" id={`cat-${group.category}`}>
					<span class="swatch" style:background={`var(--category-${group.category})`}></span>
					{group.category.toUpperCase()}
					{#if !group.suggested}<span class="count">{group.total}</span>{/if}
				</h3>
				{#each group.types as t (t.type)}
					{@render stepEntry(t, group.suggested)}
				{/each}
				{#if group.hidden > 0}
					<button type="button" class="more" aria-expanded="false" onclick={() => expand(group.category)}>
						Show {group.hidden} more
					</button>
				{/if}
			</section>
		{:else}
			<p class="empty">No step type matches “{query}”.</p>
		{/each}
		{#if view.unsupported.length > 0}
			<!-- Spec 004 D-1 / spec 023 FR-013: still listed (saved flows use them), gathered here. -->
			<section class="group unsupported" aria-labelledby="cat-unsupported">
				<h3 class="group-title" id="cat-unsupported">
					{view.unsupported.length} types not supported in v1
					{#if !expanded.has(UNSUPPORTED)}
						<button type="button" class="more inline" aria-expanded="false" onclick={() => expand(UNSUPPORTED)}>Show</button>
					{/if}
				</h3>
				{#if expanded.has(UNSUPPORTED)}
					{#each view.unsupported as t (t.type)}
						{@render stepEntry(t, false)}
					{/each}
				{/if}
			</section>
		{/if}
	</div>
</aside>

<style>
	.count {
		margin-left: auto;
		font-family: var(--font-mono);
		font-weight: 500;
		letter-spacing: 0;
		color: var(--color-text-muted);
	}

	.more {
		align-self: flex-start;
		font: inherit;
		font-size: var(--size-caption);
		color: var(--color-text-muted);
		background: transparent;
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-control);
		padding: 3px 8px;
		cursor: pointer;
	}

	.more.inline {
		margin-left: auto;
		padding: 1px 6px;
		letter-spacing: 0;
	}

	.palette {
		display: flex;
		flex-direction: column;
		width: var(--chrome-palette-width);
		flex-shrink: 0;
		box-sizing: border-box;
		background: var(--color-ground-rail);
		border-right: 1px solid var(--color-border-faint);
		min-height: 0;
	}

	.head {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-loose) var(--space-loose) var(--space-base);
	}

	.label {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--size-caption);
		font-weight: 600;
		letter-spacing: 0.12em;
		color: var(--color-text-muted);
	}

	input {
		box-sizing: border-box;
		width: 100%;
		font: inherit;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 9px;
	}

	.groups {
		display: flex;
		flex-direction: column;
		gap: var(--space-section);
		padding: 0 var(--space-loose) var(--space-loose);
		overflow-y: auto;
	}

	.group {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.group-title {
		display: flex;
		align-items: center;
		gap: 7px;
		margin: 0;
		font-size: var(--size-caption);
		font-weight: 600;
		letter-spacing: 0.06em;
		color: var(--color-text-muted);
	}

	.swatch {
		width: 8px;
		height: 8px;
	}

	.entry {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		box-sizing: border-box;
		width: 100%;
		padding: 8px 9px 8px 12px;
		text-align: left;
		font: inherit;
		color: inherit;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-left: 3px solid var(--entry-category);
		border-radius: var(--radius-control);
		box-shadow: var(--color-card-shadow);
		cursor: grab;
	}

	.entry:hover {
		background: var(--color-card-raised);
		border-color: var(--color-border-strong);
		border-left-color: var(--entry-category);
	}

	.entry.unavailable {
		cursor: not-allowed;
		opacity: 0.6;
		box-shadow: none;
	}

	.entry.unavailable:hover {
		background: var(--color-card);
		border-color: var(--color-border);
		border-left-color: var(--entry-category);
	}

	.entry-unavailable {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		color: var(--color-text-muted);
	}

	.entry-text {
		display: flex;
		flex-direction: column;
		gap: 1px;
		/* A flex child shrinks below its content only with min-width: 0 (long class names). */
		min-width: 0;
	}

	.entry-name {
		font-size: var(--size-body);
		font-weight: 600;
		color: var(--color-text);
	}

	.entry-class {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		color: var(--color-text-muted);
		/* Long names break after a dot (<wbr>); anywhere only when one segment is still too wide. */
		overflow-wrap: anywhere;
	}

	.hazard-swatch {
		width: 16px;
		height: 16px;
		flex-shrink: 0;
		border: 1px solid var(--destructive-accent);
		background: repeating-linear-gradient(45deg, var(--destructive-accent) 0 3px, var(--color-card) 3px 6px);
	}

	.empty {
		margin: 0;
		font-size: var(--size-body);
		color: var(--color-text-muted);
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}
</style>
