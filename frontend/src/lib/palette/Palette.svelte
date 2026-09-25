<script lang="ts">
	import { STEP_TYPE_MIME } from '$lib/canvas/dnd';
	import { stepLabel, type StepCategory, type StepTypeInfo } from '$lib/flow/document';

	let { registry, onadd }: { registry: StepTypeInfo[]; onadd: (type: string) => void } = $props();

	const ORDER: StepCategory[] = ['verification', 'storage', 'journal', 'purge', 'backup', 'custom'];

	let query = $state('');

	const groups = $derived.by(() => {
		const q = query.trim().toLowerCase();
		const matches = registry.filter(
			(t) =>
				!q ||
				t.type.includes(q) ||
				stepLabel(t.type).toLowerCase().includes(q) ||
				t.className.toLowerCase().includes(q)
		);
		return ORDER.map((category) => ({
			category,
			types: matches.filter((t) => t.category === category)
		})).filter((g) => g.types.length > 0);
	});

	function ondragstart(event: DragEvent, type: string) {
		event.dataTransfer?.setData(STEP_TYPE_MIME, type);
		if (event.dataTransfer) event.dataTransfer.effectAllowed = 'copy';
	}
</script>

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
				</h3>
				{#each group.types as t (t.type)}
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
						title={t.available
							? 'Drag onto the canvas, or press Enter to add'
							: 'Not supported on the target platform in v1'}
						ondragstart={(e) => ondragstart(e, t.type)}
						onclick={() => onadd(t.type)}
					>
						<span class="entry-text">
							<span class="entry-name">{stepLabel(t.type)}</span>
							<span class="entry-class">{t.className || 'subclass of %SYS.Task.Definition'}</span>
							{#if !t.available}<span class="entry-unavailable">not supported in v1</span>{/if}
						</span>
						{#if t.destructive}
							<span class="hazard-swatch" title="Destructive step" aria-label="Destructive step"></span>
						{/if}
					</button>
				{/each}
			</section>
		{:else}
			<p class="empty">No step type matches “{query}”.</p>
		{/each}
	</div>
</aside>

<style>
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
