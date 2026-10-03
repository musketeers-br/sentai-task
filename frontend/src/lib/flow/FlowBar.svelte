<script lang="ts">
	import MenuButton from '$lib/shell/MenuButton.svelte';
	import type { FlowEditor } from './editor.svelte';
	import { flowBarState } from './flowbar';

	// Spec 023 US1 (FR-005, FR-006): the open flow's own bar, under the global top bar. Everything
	// that belongs to the flow lives here; the top bar keeps only what is the same on every screen.
	let {
		editor,
		onopen,
		onsave,
		onsaveas,
		onnew,
		onvalidate,
		onrun,
		onschedule,
		onhistory
	}: {
		editor: FlowEditor;
		/** Spec 010 FR-002: one click to the list (SC-002), so never inside a menu. */
		onopen: () => void;
		onsave: () => void;
		/** Spec 010 FR-004 / FR-007. */
		onsaveas: () => void;
		onnew: () => void;
		onvalidate: () => void;
		onrun: () => void;
		onschedule: () => void;
		/** Spec 012 FR-010: the Runs screen filtered to the open flow. */
		onhistory: () => void;
	} = $props();

	const state = $derived(
		flowBarState({
			steps: editor.steps.length,
			id: editor.id,
			revision: editor.revision,
			savedAt: editor.savedAt,
			dirty: editor.dirty,
			validating: editor.validating,
			scheduleBlocked: editor.scheduleBlocked
		})
	);
	const canSave = $derived(!editor.saving && (editor.dirty || editor.id === null));
	const RENAME_NOTE = 'Renames this flow — use Save as… to keep a copy';
</script>

<div class="flow-bar" role="toolbar" aria-label="Flow">
	<span class="name-field">
		<label for="flow-name" class="visually-hidden">Flow name</label>
		<input
			id="flow-name"
			class="flow-name"
			bind:value={editor.name}
			oninput={() => editor.touch('cosmetic')}
			spellcheck="false"
		/>
		<!-- Spec 010 FR-005: said before saving, so a rename is never mistaken for a copy. -->
		{#if editor.renaming}<span class="rename-note" role="status">{RENAME_NOTE}</span>{/if}
	</span>
	<span class="ns-chip" title="Task Manager namespace">%SYS</span>
	{#if state.saveState.kind === 'unsaved'}
		<span class="badge" data-testid="flow-meta">unsaved</span>
	{:else}
		<span class="meta" data-testid="flow-meta">{state.meta}</span>
	{/if}

	<button type="button" class="secondary" onclick={onopen}>Open…</button>
	<button
		type="button"
		class="secondary"
		disabled={!canSave}
		title={editor.renaming ? RENAME_NOTE : undefined}
		onclick={onsave}
	>
		{editor.saving ? 'Saving…' : 'Save'}
	</button>

	<span class="spacer"></span>

	{#if state.reason}
		<span class="reason" role="status" data-testid="flow-actions-reason">{state.reason}</span>
	{/if}
	<!-- Spec 021 FR-002: the tour's third mark anchors to these two controls. -->
	<button
		type="button"
		class="secondary"
		data-tour-target="validate"
		disabled={!state.actions.validate.enabled}
		onclick={onvalidate}
	>
		{editor.validating ? 'Validating…' : 'Validate'}
	</button>
	<button
		type="button"
		class="primary"
		data-tour-target="run"
		disabled={!state.actions.run.enabled}
		title={state.actions.run.enabled ? 'Dispatch this flow now' : undefined}
		onclick={onrun}
	>
		Run now
	</button>
	<button
		type="button"
		class="secondary"
		disabled={!state.actions.schedule.enabled}
		title={state.actions.schedule.enabled ? 'Schedule in Task Manager' : undefined}
		onclick={onschedule}
	>
		Schedule
	</button>
	<MenuButton
		id="flow-more"
		label="⋯"
		ariaLabel="More flow actions"
		caret={false}
		items={[
			{ label: 'New flow', onselect: onnew },
			{ label: 'Save as…', disabled: editor.saving || editor.name.trim() === '', onselect: onsaveas },
			{ label: 'Run history', disabled: editor.id === null, onselect: onhistory }
		]}
	/>
</div>

<style>
	.flow-bar {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px;
		min-height: var(--chrome-top-bar-height);
		flex-shrink: 0;
		box-sizing: border-box;
		padding: 6px var(--space-section);
		background: var(--color-ground-rail);
		border-bottom: 1px solid var(--color-border-faint);
	}

	.name-field {
		position: relative;
		display: flex;
		flex: 0 1 280px;
		min-width: 120px;
	}

	.flow-name {
		flex: 1 1 auto;
		min-width: 0;
		text-overflow: ellipsis;
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

	.rename-note {
		position: absolute;
		top: calc(100% + 6px);
		left: 0;
		z-index: 5;
		white-space: nowrap;
		font-size: var(--size-caption);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		box-shadow: var(--color-card-shadow);
		padding: 4px 8px;
	}

	.ns-chip {
		flex-shrink: 0;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-chip);
		padding: 1px 6px;
	}

	.meta,
	.reason {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
		white-space: nowrap;
	}

	.badge {
		flex-shrink: 0;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		font-weight: 600;
		color: var(--color-text);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-chip);
		padding: 1px 6px;
	}

	.spacer {
		flex-grow: 1;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		white-space: nowrap;
		flex-shrink: 0;
		cursor: pointer;
	}

	.primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
		border-radius: var(--radius-control);
		padding: 6px 12px;
	}

	.secondary {
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 6px 12px;
	}

	.primary:disabled,
	.secondary:disabled {
		opacity: 0.45;
		cursor: default;
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
