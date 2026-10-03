<script lang="ts">
	// Spec 022 US1/US3 (FR-001…FR-007, FR-012): the gallery that replaces the empty canvas. Cards
	// render the shipped runbooks (runbooks.ts, data not code); the verdicts are pure view-model
	// work (runbookCards.ts) derived from the registry and the registered targets the page passes
	// in; the mini-graph is pure geometry (miniGraph.ts). No fetch, no storage — the page owns
	// wiring and every platform refusal passes through it verbatim (Constitution III/IV).
	import type { StepTypeInfo } from '$lib/flow/document';
	import MiniGraph from './MiniGraph.svelte';
	import { miniGraph } from './miniGraph';
	import { RUNBOOKS, runbookSlug, type Runbook } from './runbooks';
	import { runbookCards } from './runbookCards';

	let {
		runbooks = RUNBOOKS,
		registry,
		targets = [],
		onuse,
		onstartblank
	}: {
		runbooks?: readonly Runbook[];
		registry: readonly StepTypeInfo[];
		/** Registered target names, refetched by the page every time the gallery shows (FR-007). */
		targets?: readonly string[];
		onuse: (runbook: Runbook) => void;
		onstartblank: () => void;
	} = $props();

	const cards = $derived(runbookCards(runbooks, registry, targets));
</script>

<section class="gallery" data-testid="runbook-gallery" aria-label="Runbooks">
	<header class="head">
		<h2>Start with a runbook</h2>
		<button type="button" class="secondary" data-testid="start-from-scratch" onclick={onstartblank}>
			Start from scratch
		</button>
	</header>
	<ul class="cards">
		{#each cards as card (card.runbook.flowName)}
			<li class="card" data-testid="runbook-card" data-runbook={runbookSlug(card.runbook.flowName)}>
				<h3>{card.runbook.title}</h3>
				<p class="purpose">{card.runbook.purpose}</p>
				{#if card.cadence}
					<p class="cadence" data-testid="runbook-card-cadence">Suggested: {card.cadence}</p>
				{/if}
				<!-- FR-005: the steps the runbook runs, destructive content marked as such. -->
				<ul class="steps">
					{#each card.steps as step (step.id)}
						<li class:destructive={step.destructive}>
							{step.label}{#if step.onTarget}<span class="remote"> on {step.onTarget}</span>{/if}
							{#if step.destructive}<span class="flag">destructive</span>{/if}
						</li>
					{/each}
				</ul>
				<MiniGraph graph={miniGraph(card.runbook.definition, registry)} slug={runbookSlug(card.runbook.flowName)} />
				{#if card.availability.kind === 'unavailable'}
					<!-- FR-007: shown, not clickable into a dead end, with the reason. -->
					<button type="button" class="primary" data-testid="runbook-card-use" disabled>
						Use
					</button>
					<p class="reason" data-testid="runbook-card-reason">{card.availability.reason}</p>
				{:else}
					<button type="button" class="primary" data-testid="runbook-card-use" onclick={() => onuse(card.runbook)}>
						Use
					</button>
				{/if}
			</li>
		{/each}
	</ul>
</section>

<style>
	.gallery {
		position: absolute;
		inset: 6px 12px 12px 12px;
		z-index: 4;
		display: flex;
		flex-direction: column;
		gap: 12px;
		overflow-y: auto;
		color: var(--color-text);
		background: var(--color-ground);
	}

	.head {
		display: flex;
		align-items: baseline;
		flex-wrap: wrap;
		gap: 12px;
		justify-content: space-between;
		/* Spec 021's Tour control is pinned to the canvas' top-right corner (offset 12px +
		   ~60px wide) and stays above the gallery (z-index 5); the header reserves that
		   footprint so *Start from scratch* never renders underneath it. On the smallest
		   viewport the row wraps instead of sliding back under the Tour button. */
		padding: 4px 72px 0 4px;
	}

	h2 {
		margin: 0;
		font-size: var(--size-sectionTitle);
		font-weight: 600;
	}

	h3 {
		margin: 0;
		font-size: var(--size-bodyStrong);
		font-weight: 600;
	}

	.head button,
	.card button {
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 7px 14px;
		cursor: pointer;
	}

	.secondary {
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
	}

	.primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
	}

	.cards {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(272px, 1fr));
		gap: 14px;
		margin: 0;
		padding: 0 4px 8px;
		list-style: none;
	}

	.card {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 14px 16px 16px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: var(--color-card-shadow);
	}

	.card .primary {
		align-self: flex-end;
	}

	.purpose {
		margin: 0;
		font-size: var(--size-body);
		line-height: 1.5;
		color: var(--color-text-muted);
	}

	.cadence {
		margin: -4px 0 0;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.steps {
		display: flex;
		flex-wrap: wrap;
		gap: 4px 10px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.steps li {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.steps li.destructive {
		color: var(--destructive-accent);
	}

	.steps .remote {
		font-family: var(--font-mono);
	}

	.steps .flag {
		margin-left: 4px;
		padding: 0 4px;
		font-family: var(--font-mono);
		font-size: 9px;
		text-transform: uppercase;
		border: 1px solid var(--destructive-accent);
		border-radius: 3px;
	}

	.reason {
		margin: 0;
		align-self: flex-end;
		font-size: var(--size-caption);
		font-style: italic;
		color: var(--color-text-muted);
	}

	button:disabled {
		font-weight: 600;
		color: var(--color-text-muted);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		cursor: not-allowed;
	}
</style>
