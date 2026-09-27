<script lang="ts">
	import Mark from './Mark.svelte';
	import MenuButton from './MenuButton.svelte';
	import { theme } from './theme.svelte';
	import type { FlowEditor } from '$lib/flow/editor.svelte';
	import type { Screen } from './screen';

	let {
		editor,
		screen,
		onnavigate,
		user,
		onsave,
		onsaveas,
		onnew,
		onopen,
		onvalidate,
		onrun,
		onschedule,
		onhelp,
		onsignout
	}: {
		editor: FlowEditor;
		screen: Screen;
		onnavigate: (screen: Screen) => void;
		user: string | null;
		onsave: () => void;
		/** Spec 010 FR-004 / FR-007. */
		onsaveas: () => void;
		onnew: () => void;
		/** Spec 010 FR-002: one click to the list (SC-002), so never inside a menu. */
		onopen: () => void;
		onvalidate: () => void;
		onrun: () => void;
		onschedule: () => void;
		/** Spec 010 FR-023: Help → Getting started, on every screen. */
		onhelp: () => void;
		onsignout: () => void;
	} = $props();


	// Kept exactly as the platform reports it ("YYYY-MM-DD HH:MM:SS"); only the time is shown.
	const savedTime = $derived(editor.savedAt ? editor.savedAt.slice(11, 16) : null);
	const canSave = $derived(!editor.saving && (editor.dirty || editor.id === null));
	const RENAME_NOTE = 'Renames this flow — use Save as… to keep a copy';
</script>

<header class="top-bar">
	<Mark />
	<span class="separator" aria-hidden="true"></span>

	<nav class="tabs" aria-label="Screens">
		<button type="button" aria-current={screen === 'flows' ? 'page' : undefined} onclick={() => onnavigate('flows')}>
			Flows
		</button>
		<button type="button" aria-current={screen === 'catalog' ? 'page' : undefined} onclick={() => onnavigate('catalog')}>
			Task catalog
		</button>
		<button type="button" aria-current={screen === 'targets' ? 'page' : undefined} onclick={() => onnavigate('targets')}>
			Targets
		</button>
	</nav>

	{#if screen === 'flows'}
		<span class="separator" aria-hidden="true"></span>
		<button type="button" class="secondary" onclick={onopen}>Open flow…</button>
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
			<!-- Stacked under the name (spec 010): the 1440 px bar has no width left beside it. -->
			<span class="sub">
				<span class="ns-chip" title="Task Manager namespace">%SYS</span>
				<span class="meta" data-testid="flow-meta">
					{#if editor.id === null}
						not saved yet
					{:else}
						rev {editor.revision} · saved {savedTime}{editor.dirty ? ' · edited' : ''}
					{/if}
				</span>
			</span>
			{#if editor.renaming}<span class="rename-note" role="status">{RENAME_NOTE}</span>{/if}
		</span>
	{/if}

	<span class="spacer"></span>

	<div class="theme-switch" role="group" aria-label="Theme">
		<button type="button" aria-pressed={theme.current === 'dark'} onclick={() => theme.set('dark')}>Dark</button>
		<button type="button" aria-pressed={theme.current === 'light'} onclick={() => theme.set('light')}>Light</button>
	</div>

	{#if screen === 'flows'}
		<button
			type="button"
			class="secondary"
			disabled={!canSave}
			title={editor.renaming ? RENAME_NOTE : undefined}
			onclick={onsave}
		>
			{editor.saving ? 'Saving…' : 'Save flow'}
		</button>
		<!-- Spec 010 D-7 fallback: the 1440 px bar fits New flow and Save as… only in a menu. -->
		<MenuButton
			id="flow-more"
			label="More"
			items={[
				{ label: 'New flow', onselect: onnew },
				{ label: 'Save as…', disabled: editor.saving || editor.name.trim() === '', onselect: onsaveas }
			]}
		/>
		<button
			type="button"
			class="secondary"
			disabled={editor.validating || editor.steps.length === 0}
			onclick={onvalidate}
		>
			{editor.validating ? 'Validating…' : 'Validate flow'}
		</button>
		<button
			type="button"
			class="primary"
			disabled={editor.scheduleBlocked || editor.steps.length === 0}
			title={editor.scheduleBlocked ? 'Fix the validation errors listed in the status bar first' : 'Dispatch this flow now'}
			onclick={onrun}
		>
			Run now
		</button>
		<button
			type="button"
			class="secondary"
			disabled={editor.scheduleBlocked || editor.steps.length === 0}
			title={editor.scheduleBlocked ? 'Fix the validation errors listed in the status bar first' : undefined}
			onclick={onschedule}
		>
			Schedule in Task Manager
		</button>
	{/if}

	<MenuButton id="help" label="Help" items={[{ label: 'Getting started', onselect: onhelp }]} />
	<span class="user">{user}</span>
	<button type="button" class="quiet" onclick={onsignout}>Sign out</button>
</header>

<style>
	.top-bar {
		display: flex;
		align-items: center;
		/* Three tabs plus the flow actions must fit 1440 px without clipping (spec 009, spec 010). */
		gap: 8px;
		height: var(--chrome-top-bar-height);
		flex-shrink: 0;
		box-sizing: border-box;
		padding: 0 var(--space-section);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
	}

	.tabs {
		display: flex;
		gap: 4px;
	}

	.tabs button {
		font-weight: 500;
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-control);
		padding: 6px 10px;
	}

	.tabs button[aria-current='page'] {
		font-weight: 600;
		color: var(--color-text);
		background: var(--color-card);
		border-color: var(--color-border);
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

	.name-field {
		position: relative;
		display: flex;
		flex-direction: column;
		justify-content: center;
		flex: 0 1 240px;
		min-width: 112px;
		gap: 1px;
	}

	.name-field .sub {
		display: flex;
		align-items: center;
		gap: 6px;
		min-width: 0;
		padding: 0 7px;
	}

	.name-field .meta {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.name-field .ns-chip {
		flex-shrink: 0;
		padding: 0 5px;
		line-height: 1.4;
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

	.flow-name {
		/* Spec 009 added a third tab: the name gives way first, so nothing else wraps or clips. */
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
		padding: 2px 6px;
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
		color: var(--color-text-muted);
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
		white-space: nowrap;
		flex-shrink: 0;
		cursor: pointer;
	}

	.tabs,
	.theme-switch,
	.meta,
	.user {
		flex-shrink: 0;
		white-space: nowrap;
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
		padding: 7px 10px;
	}

	.secondary {
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 10px;
	}

	.primary:disabled,
	.secondary:disabled {
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
