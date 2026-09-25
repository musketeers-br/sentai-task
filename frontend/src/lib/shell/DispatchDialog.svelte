<script lang="ts">
	import { session } from '$lib/api/session.svelte';
	import type { FlowEditor } from '$lib/flow/editor.svelte';

	let {
		editor,
		open = $bindable(false),
		ondispatched
	}: { editor: FlowEditor; open: boolean; ondispatched: (guid: string) => void } = $props();

	let dialog: HTMLDialogElement;
	let password = $state('');
	let busy = $state(false);
	let message = $state<string | null>(null);

	$effect(() => {
		if (open && !dialog.open) {
			message = null;
			dialog.showModal();
		} else if (!open && dialog.open) {
			dialog.close();
		}
	});

	async function onsubmit(event: SubmitEvent) {
		event.preventDefault();
		busy = true;
		const result = await editor.dispatch(password);
		busy = false;
		password = '';
		if (result.ok) {
			open = false;
			ondispatched(result.guid);
		} else {
			message = result.message;
		}
	}
</script>

<dialog bind:this={dialog} onclose={() => (open = false)} aria-labelledby="dispatch-title">
	<form {onsubmit}>
		<h2 id="dispatch-title">Run {editor.name} now</h2>
		<p class="lead">
			The run is dispatched under its own sign-in, so it gets the full credential lifetime whatever
			this screen does meanwhile.
		</p>
		<p class="limitation">
			v1 limitation: a run's credential lasts 60 seconds. Platform calls made later fail with HTTP 401,
			recorded as the step's failure reason — keep runs short.
		</p>

		<label for="dispatch-password">Password for {session.user}</label>
		<input id="dispatch-password" type="password" autocomplete="current-password" required bind:value={password} />

		{#if message}<p class="error" role="alert">{message}</p>{/if}

		<div class="actions">
			<button type="button" class="quiet" onclick={() => (open = false)}>Cancel</button>
			<button type="submit" class="primary" disabled={busy}>{busy ? 'Dispatching…' : 'Dispatch'}</button>
		</div>
	</form>
</dialog>

<style>
	dialog {
		width: 440px;
		padding: 0;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: 0 12px 40px rgba(0, 0, 0, 0.35);
	}

	dialog::backdrop {
		background: color-mix(in srgb, var(--color-ground) 70%, transparent);
	}

	form {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 22px;
	}

	h2 {
		margin: 0;
		font-size: var(--size-sectionTitle);
		font-weight: 600;
	}

	.lead,
	.limitation,
	.error {
		margin: 0;
		font-size: var(--size-body);
		line-height: 1.5;
	}

	.lead {
		color: var(--color-text-muted);
	}

	.limitation {
		margin-bottom: 8px;
		padding: 9px 10px;
		font-size: var(--size-caption);
		color: var(--warning-body);
		background: var(--warning-surface);
		border: 1px solid var(--warning-border);
		border-radius: var(--radius-control);
	}

	.error {
		color: var(--destructive-text);
	}

	label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	input {
		font: inherit;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-ground);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 8px 9px;
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
		margin-top: 8px;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 7px 14px;
		cursor: pointer;
	}

	.primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
	}

	.primary:disabled {
		opacity: 0.45;
	}

	.quiet {
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
	}
</style>
