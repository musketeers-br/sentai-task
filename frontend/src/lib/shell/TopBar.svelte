<script lang="ts">
	import Mark from './Mark.svelte';
	import { theme } from './theme.svelte';
	import type { FlowEditor } from '$lib/flow/editor.svelte';

	let {
		editor,
		user,
		onsave,
		onsignout
	}: { editor: FlowEditor; user: string | null; onsave: () => void; onsignout: () => void } = $props();

	// Kept exactly as the platform reports it ("YYYY-MM-DD HH:MM:SS"); only the time is shown.
	const savedTime = $derived(editor.savedAt ? editor.savedAt.slice(11, 16) : null);
	const canSave = $derived(!editor.saving && (editor.dirty || editor.id === null));
</script>

<header class="top-bar">
	<Mark />
	<span class="separator" aria-hidden="true"></span>

	<span class="ns-chip" title="Task Manager namespace">%SYS</span>
	<label for="flow-name" class="visually-hidden">Flow name</label>
	<input
		id="flow-name"
		class="flow-name"
		bind:value={editor.name}
		oninput={() => editor.touch()}
		spellcheck="false"
	/>
	<span class="meta" data-testid="flow-meta">
		{#if editor.id === null}
			not saved yet
		{:else}
			rev {editor.revision} · saved {savedTime}{editor.dirty ? ' · edited' : ''}
		{/if}
	</span>

	<span class="spacer"></span>

	<div class="theme-switch" role="group" aria-label="Theme">
		<button type="button" aria-pressed={theme.current === 'dark'} onclick={() => theme.set('dark')}>Dark</button>
		<button type="button" aria-pressed={theme.current === 'light'} onclick={() => theme.set('light')}>Light</button>
	</div>

	<button type="button" class="primary" disabled={!canSave} onclick={onsave}>
		{editor.saving ? 'Saving…' : 'Save flow'}
	</button>

	<span class="user">{user}</span>
	<button type="button" class="quiet" onclick={onsignout}>Sign out</button>
</header>

<style>
	.top-bar {
		display: flex;
		align-items: center;
		gap: var(--space-section);
		height: var(--chrome-top-bar-height);
		flex-shrink: 0;
		box-sizing: border-box;
		padding: 0 var(--space-section);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
	}

	.separator {
		width: 1px;
		height: 24px;
		background: var(--color-border-faint);
	}

	.ns-chip {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-chip);
		padding: 3px 7px;
	}

	.flow-name {
		min-width: 220px;
		font: inherit;
		font-size: var(--size-bodyStrong);
		font-weight: 600;
		color: var(--color-text);
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-control);
		padding: 4px 6px;
	}

	.flow-name:hover,
	.flow-name:focus {
		border-color: var(--color-border);
		background: var(--color-card);
	}

	.meta,
	.user {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-faint);
	}

	.spacer {
		flex-grow: 1;
	}

	.theme-switch {
		display: flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		overflow: hidden;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		cursor: pointer;
	}

	.theme-switch button {
		font-size: var(--size-caption);
		font-weight: 500;
		color: var(--color-text-muted);
		background: transparent;
		border: 0;
		padding: 6px 10px;
	}

	.theme-switch button[aria-pressed='true'] {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
	}

	.primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
		border-radius: var(--radius-control);
		padding: 7px 14px;
	}

	.primary:disabled {
		opacity: 0.45;
		cursor: default;
	}

	.quiet {
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 6px 10px;
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
