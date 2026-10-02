<script lang="ts">
	import type { Snippet } from 'svelte';
	import { wrapTab } from './dialog-focus';

	// Spec 010: the modal shell of the new dialogs. Native <dialog> + showModal() — the page behind
	// is inert, so focus stays inside; Escape fires `cancel`. Focus goes back to whatever had it
	// before the dialog opened (FR-025), because browsers restore it inconsistently on their own.
	// Spec 021: the Tab-wrap rule lives in dialog-focus.ts, shared with the tour's overlay.
	let {
		open = $bindable(false),
		labelledby,
		describedby,
		width,
		onclose,
		children
	}: {
		open: boolean;
		labelledby: string;
		describedby?: string;
		width?: string;
		/** Every way the dialog closes (Escape, a button setting `open = false`) ends here once. */
		onclose?: () => void;
		children: Snippet;
	} = $props();

	let dialog: HTMLDialogElement;
	let returnFocus: Element | null = null;

	$effect(() => {
		if (open && !dialog.open) {
			returnFocus = document.activeElement;
			dialog.showModal();
		} else if (!open && dialog.open) {
			dialog.close();
		}
	});

	/** FR-025: Tab wraps inside the dialog instead of leaving the page for the browser's chrome. */
	function onkeydown(event: KeyboardEvent) {
		wrapTab(dialog, event);
	}

	function closed() {
		// `onclose` first: it still sees the dialog as open (the guide keeps its choice then).
		onclose?.();
		open = false;
		if (returnFocus instanceof HTMLElement && returnFocus.isConnected) returnFocus.focus();
		returnFocus = null;
	}
</script>

<dialog
	bind:this={dialog}
	class="modal"
	aria-modal="true"
	aria-labelledby={labelledby}
	aria-describedby={describedby}
	style:width
	onclose={closed}
	{onkeydown}
>
	{#if open}{@render children()}{/if}
</dialog>
