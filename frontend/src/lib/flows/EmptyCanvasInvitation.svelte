<script lang="ts">
	// Spec 010 FR-016(a): on the empty canvas of an instance with no saved flows. The example is
	// offered only when its step types are declared, available and non-destructive (FR-019).
	let {
		showExample,
		onexample,
		ondismiss
	}: { showExample: boolean; onexample: () => void; ondismiss: () => void } = $props();
</script>

<section class="invitation" data-testid="example-invitation" aria-labelledby="invitation-title">
	<h2 id="invitation-title">Start with a ready-made flow</h2>
	<p>Open a small example of safe, read-only checks and run it on this instance.</p>
	<div class="actions">
		{#if showExample}
			<button type="button" class="primary" onclick={onexample}>Open example flow</button>
		{/if}
		<button type="button" class="secondary" onclick={ondismiss}>Start from scratch</button>
	</div>
</section>

<style>
	.invitation {
		position: absolute;
		top: 50%;
		left: 50%;
		z-index: 4;
		display: flex;
		flex-direction: column;
		gap: 10px;
		width: 360px;
		padding: 22px;
		transform: translate(-50%, -50%);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: var(--color-card-shadow);
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
		gap: 8px;
		margin-top: 6px;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 7px 14px;
		cursor: pointer;
	}

	.primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
	}

	.secondary {
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
	}
</style>
