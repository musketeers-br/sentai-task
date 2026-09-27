<script lang="ts">
	import Modal from '$lib/shell/Modal.svelte';
	import { guide } from './guide.svelte';

	// Spec 010 FR-021/FR-025: six steps, one at a time, as a modal dialog announced with its title.
	// Modal.svelte keeps focus inside, closes on Escape and returns focus to where it was.
	let { showExample, onexample }: { showExample: boolean; onexample: () => void } = $props();

	const current = $derived(guide.steps[guide.step - 1]);
	const last = $derived(guide.step === guide.steps.length);
</script>

<Modal bind:open={guide.open} labelledby="guide-title" describedby="guide-step-body" width="480px" onclose={() => guide.close()}>
	<div class="modal-body">
		<h2 id="guide-title">Getting started</h2>
		<p class="indicator" aria-live="polite">Step {guide.step} of {guide.steps.length}</p>
		<!-- svelte-ignore a11y_autofocus -->
		<h3 class="step-title" data-testid="guide-step-title" tabindex="-1" autofocus>{current.title}</h3>
		<p class="lead" id="guide-step-body" data-testid="guide-step-body">{current.body}</p>
		{#if current.action === 'open-example' && showExample}
			<div class="step-action">
				<button type="button" class="secondary" onclick={onexample}>Open example flow</button>
			</div>
		{/if}

		<label class="dont-show">
			<input type="checkbox" bind:checked={guide.dontShow} />
			Don't show this again
		</label>

		<div class="actions">
			<button type="button" class="quiet" onclick={() => guide.close()}>Close</button>
			<span class="spacer"></span>
			<button type="button" class="secondary" disabled={guide.step === 1} onclick={() => guide.back()}>Back</button>
			{#if last}
				<button type="button" class="primary" onclick={() => guide.close()}>Get started</button>
			{:else}
				<button type="button" class="primary" onclick={() => guide.next()}>Next</button>
			{/if}
		</div>
	</div>
</Modal>

<style>
	.indicator {
		margin: 0;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.step-title {
		margin: 8px 0 0;
		font-size: var(--size-bodyStrong);
		font-weight: 600;
		outline: none;
	}

	.lead {
		min-height: 4.5em;
	}

	.step-action {
		margin-bottom: 4px;
	}

	.dont-show {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		margin-top: 8px;
		font-size: var(--size-body);
		color: var(--color-text);
		cursor: pointer;
	}

	.spacer {
		flex-grow: 1;
	}
</style>
