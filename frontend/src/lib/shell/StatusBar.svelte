<script lang="ts">
	import { formatSummary } from '$lib/flow/document';
	import type { FlowEditor } from '$lib/flow/editor.svelte';

	let { editor }: { editor: FlowEditor } = $props();
</script>

<footer class="status-bar">
	<span data-testid="flow-summary">{formatSummary(editor.summary)}</span>
	{#if editor.notice}
		<span class={`notice ${editor.notice.tone}`} role="status">
			{editor.notice.text}
			<button type="button" aria-label="Dismiss message" onclick={() => (editor.notice = null)}>×</button>
		</span>
	{/if}
	<span class="spacer"></span>
	<span class="faint">snap 8 px</span>
	<span class="faint" data-testid="zoom">zoom {Math.round(editor.zoom * 100)}%</span>
</footer>

<style>
	.status-bar {
		display: flex;
		align-items: center;
		gap: var(--space-section);
		height: var(--chrome-status-bar-height);
		flex-shrink: 0;
		box-sizing: border-box;
		padding: 0 var(--space-loose);
		background: var(--color-surface);
		border-top: 1px solid var(--color-border-faint);
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.spacer {
		flex-grow: 1;
	}

	.faint {
		color: var(--color-text-faint);
	}

	.notice {
		display: inline-flex;
		align-items: center;
		gap: 8px;
	}

	.notice.error {
		color: var(--destructive-text);
	}

	.notice button {
		font: inherit;
		color: inherit;
		background: transparent;
		border: 0;
		cursor: pointer;
	}
</style>
