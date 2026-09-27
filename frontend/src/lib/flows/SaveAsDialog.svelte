<script lang="ts">
	import { untrack } from 'svelte';
	import { describeError } from '$lib/api/client';
	import type { FlowEditor } from '$lib/flow/editor.svelte';
	import Modal from '$lib/shell/Modal.svelte';

	// Spec 010 FR-004: a new flow from this canvas under another name; the open flow is not changed.
	// The platform's refusal (a taken name, a denial) is shown as-is and the dialog stays open.
	let {
		editor,
		open = $bindable(false),
		onsaved
	}: { editor: FlowEditor; open: boolean; onsaved: (flowId: string) => void } = $props();

	let name = $state('');
	let message = $state<string | null>(null);
	let busy = $state(false);
	let input = $state<HTMLInputElement>();

	$effect(() => {
		if (open) {
			name = untrack(() => `${editor.name} copy`);
			message = null;
			queueMicrotask(() => input?.select());
		}
	});

	async function onsubmit(event: SubmitEvent) {
		event.preventDefault();
		busy = true;
		const result = await editor.saveAs(name.trim());
		busy = false;
		if (!result.ok) {
			message = describeError(result.error);
			return;
		}
		open = false;
		onsaved(result.value.id!);
	}
</script>

<Modal bind:open labelledby="save-as-title" describedby="save-as-lead">
	<form class="modal-body" {onsubmit}>
		<h2 id="save-as-title">Save as a new flow</h2>
		<p class="lead" id="save-as-lead">Creates a new flow from this canvas. The current flow is not changed.</p>
		<label for="save-as-name">Name</label>
		<input id="save-as-name" bind:this={input} bind:value={name} required spellcheck="false" autocomplete="off" />
		{#if message}<p class="error" role="alert">{message}</p>{/if}
		<div class="actions">
			<button type="button" class="quiet" onclick={() => (open = false)}>Cancel</button>
			<button type="submit" class="primary" disabled={busy || name.trim() === ''}>{busy ? 'Saving…' : 'Save as'}</button>
		</div>
	</form>
</Modal>
