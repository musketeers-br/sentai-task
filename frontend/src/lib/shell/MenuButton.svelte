<script module lang="ts">
	export interface MenuItem {
		label: string;
		disabled?: boolean;
		onselect: () => void;
	}
</script>

<script lang="ts">
	import { tick } from 'svelte';

	// Spec 010: a WAI-ARIA menu button (the top bar's *More ▾* and *Help ▾*). Enter/Space/ArrowDown
	// open it on the first item, ArrowUp on the last; arrows move, Home/End jump, Escape closes and
	// returns focus to the button; Tab or a click elsewhere closes it.

	let { label, items, id }: { label: string; items: MenuItem[]; id: string } = $props();

	let open = $state(false);
	let button: HTMLButtonElement;
	let menu = $state<HTMLElement>();

	const entries = () => [...(menu?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not(:disabled)') ?? [])];

	async function show(focus: 'first' | 'last') {
		open = true;
		await tick();
		const list = entries();
		(focus === 'first' ? list[0] : list[list.length - 1])?.focus();
	}

	function hide(returnFocus: boolean) {
		open = false;
		if (returnFocus) button.focus();
	}

	function onbuttonkey(event: KeyboardEvent) {
		if (event.key === 'ArrowDown' || event.key === 'Enter' || event.key === ' ') {
			event.preventDefault();
			void show('first');
		} else if (event.key === 'ArrowUp') {
			event.preventDefault();
			void show('last');
		}
	}

	function onmenukey(event: KeyboardEvent) {
		const list = entries();
		const at = list.indexOf(document.activeElement as HTMLButtonElement);
		const move = (i: number) => list[(i + list.length) % list.length]?.focus();
		if (event.key === 'ArrowDown') move(at + 1);
		else if (event.key === 'ArrowUp') move(at - 1);
		else if (event.key === 'Home') move(0);
		else if (event.key === 'End') move(list.length - 1);
		else if (event.key === 'Escape') hide(true);
		else if (event.key === 'Tab') hide(false);
		else return;
		if (event.key !== 'Tab') event.preventDefault();
	}

	function select(item: MenuItem) {
		hide(true);
		item.onselect();
	}

	function onwindowclick(event: MouseEvent) {
		if (open && !button.contains(event.target as Node) && !menu?.contains(event.target as Node)) hide(false);
	}
</script>

<svelte:window onclick={onwindowclick} />

<span class="menu-button">
	<button
		bind:this={button}
		type="button"
		class="trigger"
		id={`${id}-button`}
		aria-haspopup="menu"
		aria-expanded={open}
		aria-controls={`${id}-menu`}
		onclick={() => (open ? hide(false) : void show('first'))}
		onkeydown={onbuttonkey}
	>
		{label}<span class="caret" aria-hidden="true">▾</span>
	</button>
	{#if open}
		<div bind:this={menu} class="menu" role="menu" id={`${id}-menu`} aria-labelledby={`${id}-button`} tabindex="-1" onkeydown={onmenukey}>
			{#each items as item (item.label)}
				<button type="button" role="menuitem" tabindex="-1" disabled={item.disabled} onclick={() => select(item)}>
					{item.label}
				</button>
			{/each}
		</div>
	{/if}
</span>

<style>
	.menu-button {
		position: relative;
		flex-shrink: 0;
	}

	.trigger {
		font: inherit;
		font-size: var(--size-body);
		font-weight: 500;
		white-space: nowrap;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 10px;
		cursor: pointer;
	}

	.caret {
		margin-left: 5px;
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.menu {
		position: absolute;
		top: calc(100% + 4px);
		right: 0;
		z-index: 20;
		display: flex;
		flex-direction: column;
		min-width: 170px;
		padding: 4px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		box-shadow: var(--color-card-shadow);
	}

	.menu button {
		font: inherit;
		font-size: var(--size-body);
		text-align: left;
		white-space: nowrap;
		color: var(--color-text);
		background: transparent;
		border: 0;
		border-radius: var(--radius-control);
		padding: 7px 10px;
		cursor: pointer;
	}

	.menu button:hover,
	.menu button:focus-visible {
		background: var(--color-surface);
	}

	.menu button:disabled {
		opacity: 0.45;
		cursor: default;
	}
</style>
