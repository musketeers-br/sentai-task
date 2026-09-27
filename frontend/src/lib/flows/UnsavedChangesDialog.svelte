<script lang="ts">
	import Modal from '$lib/shell/Modal.svelte';
	import type { GuardChoice } from './guard';

	// Spec 010 FR-006: asked before New flow, Open flow…, Open example flow or an address change
	// replaces a flow with unsaved edits. A refused save is shown verbatim and keeps it open.
	let {
		open = $bindable(false),
		name,
		busy = false,
		message = null,
		onchoose
	}: {
		open: boolean;
		name: string;
		busy?: boolean;
		message?: string | null;
		onchoose: (choice: GuardChoice) => void;
	} = $props();

	// Escape and the Cancel button both end in `onclose`; only an explicit choice sets this first.
	let chosen = false;
	function choose(choice: GuardChoice) {
		chosen = true;
		onchoose(choice);
	}
	function onclose() {
		if (!chosen) onchoose('cancel');
		chosen = false;
	}
</script>

<Modal bind:open labelledby="unsaved-title" describedby="unsaved-lead" {onclose}>
	<div class="modal-body">
		<h2 id="unsaved-title">Save changes to "{name}"?</h2>
		<p class="lead" id="unsaved-lead">This flow has changes that are not saved.</p>
		{#if message}<p class="error" role="alert">{message}</p>{/if}
		<div class="actions">
			<button type="button" class="quiet" onclick={() => (open = false)}>Cancel</button>
			<button type="button" class="secondary" disabled={busy} onclick={() => choose('discard')}>Discard</button>
			<button type="button" class="primary" disabled={busy} onclick={() => choose('save')}>{busy ? 'Saving…' : 'Save'}</button>
		</div>
	</div>
</Modal>
