<script lang="ts">
	import { formatSummary } from '$lib/flow/document';
	import type { FlowEditor } from '$lib/flow/editor.svelte';
	import { formatErrors, formatWarnings } from '$lib/flow/report';

	let { editor }: { editor: FlowEditor } = $props();

	const warnings = $derived(formatWarnings(editor.report));
	const errors = $derived(formatErrors(editor.report));
</script>

<footer class="status-bar">
	<span data-testid="flow-summary">{formatSummary(editor.summary)}</span>
	{#if errors}
		<span class="finding error" data-testid="status-errors" title={editor.report?.errors.map((f) => f.message).join('\n')}>
			<svg width="11" height="11" viewBox="0 0 14 14" aria-hidden="true">
				<circle cx="7" cy="7" r="5.8" fill="none" stroke="currentColor" stroke-width="1.5" />
				<path d="M7 3.8 L7 7.6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
			</svg>
			{errors}
		</span>
	{/if}
	{#if warnings}
		<span class="finding warning" data-testid="status-warnings">
			<svg width="11" height="11" viewBox="0 0 14 14" aria-hidden="true">
				<path d="M7 1.4 L13 12.2 L1 12.2 Z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" />
			</svg>
			{warnings}
		</span>
	{/if}
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
		white-space: nowrap;
		overflow: hidden;
	}

	.spacer {
		flex-grow: 1;
	}

	.faint {
		color: var(--color-text-faint);
	}

	.finding {
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}

	.finding.warning {
		color: var(--warning-title);
	}

	.finding.error,
	.notice.error {
		color: var(--destructive-text);
	}

	.notice {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.notice.info {
		color: var(--state-text-completed);
	}

	.notice button {
		font: inherit;
		color: inherit;
		background: transparent;
		border: 0;
		cursor: pointer;
	}
</style>
