<script lang="ts">
	// Spec 023 FR-007–FR-009: what an empty canvas says on any instance; the canvas keeps its own
	// sequence / join legend. The spec 010 first-run invitation (no saved flows yet) still takes
	// precedence; this is every other empty flow. The card lets pointer events through, so a step
	// dragged over it still lands on the canvas.
	let {
		showTemplate,
		ontemplate,
		onimport
	}: {
		/** Spec 010 FR-019: the example's step types are declared, available and non-destructive. */
		showTemplate: boolean;
		ontemplate: () => void;
		onimport: () => void;
	} = $props();
</script>

<section class="empty" data-testid="empty-canvas" aria-labelledby="empty-canvas-title">
	<h2 id="empty-canvas-title">This flow is empty</h2>
	<p>
		Drag a step type from the left onto the canvas. Connect several outputs into one input to make a
		join — the wave runs those steps in parallel and waits.
	</p>
	<div class="actions">
		{#if showTemplate}
			<button type="button" class="secondary" onclick={ontemplate}>Start from a template</button>
		{/if}
		<button type="button" class="secondary" onclick={onimport}>Import from the task catalog</button>
	</div>
</section>

<style>
	.empty {
		position: absolute;
		top: 50%;
		left: 50%;
		z-index: 3;
		display: flex;
		flex-direction: column;
		gap: 10px;
		width: 380px;
		padding: 22px;
		transform: translate(-50%, -50%);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: var(--color-card-shadow);
		pointer-events: none;
	}

	h2 {
		margin: 0;
		font-size: var(--size-sectionTitle);
		font-weight: 600;
	}

	p {
		margin: 0;
		font-size: var(--size-body);
		line-height: 1.5;
		color: var(--color-text-muted);
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		margin-top: 4px;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 14px;
		cursor: pointer;
		pointer-events: auto;
	}
</style>
