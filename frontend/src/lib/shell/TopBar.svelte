<script lang="ts">
	import Mark from './Mark.svelte';
	import MenuButton from './MenuButton.svelte';
	import { theme } from './theme.svelte';
	import type { Screen } from './screen';

	// Spec 023 FR-001: the same bar on every screen. The open flow's controls moved to FlowBar,
	// under this bar on Flows only.
	let {
		screen,
		onnavigate,
		user,
		onhelp,
		onsignout
	}: {
		screen: Screen;
		onnavigate: (screen: Screen) => void;
		user: string | null;
		/** Spec 010 FR-023: Help → Getting started, on every screen. */
		onhelp: () => void;
		onsignout: () => void;
	} = $props();
</script>

<header class="top-bar">
	<Mark />
	<span class="separator" aria-hidden="true"></span>

	<nav class="tabs" aria-label="Screens">
		<button type="button" aria-current={screen === 'overview' ? 'page' : undefined} onclick={() => onnavigate('overview')}>
			Overview
		</button>
		<button type="button" aria-current={screen === 'flows' ? 'page' : undefined} onclick={() => onnavigate('flows')}>
			Flows
		</button>
		<button type="button" aria-current={screen === 'catalog' ? 'page' : undefined} onclick={() => onnavigate('catalog')}>
			Task catalog
		</button>
		<button type="button" aria-current={screen === 'targets' ? 'page' : undefined} onclick={() => onnavigate('targets')}>
			Targets
		</button>
		<button type="button" aria-current={screen === 'runs' ? 'page' : undefined} onclick={() => onnavigate('runs')}>
			Runs
		</button>
	</nav>

	<span class="spacer"></span>

	<div class="theme-switch" role="group" aria-label="Theme">
		<button type="button" aria-pressed={theme.current === 'dark'} onclick={() => theme.set('dark')}>Dark</button>
		<button type="button" aria-pressed={theme.current === 'light'} onclick={() => theme.set('light')}>Light</button>
	</div>

	<MenuButton id="help" label="Help" items={[{ label: 'Getting started', onselect: onhelp }]} />
	<span class="user">{user}</span>
	<button type="button" class="quiet" onclick={onsignout}>Sign out</button>
</header>

<style>
	.top-bar {
		display: flex;
		align-items: center;
		/* Spec 023: the flow actions live in FlowBar, so the bar no longer has to squeeze (spec 019 did). */
		gap: 6px;
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
		padding: 6px 7px;
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

	.quiet {
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 6px 10px;
	}

</style>
