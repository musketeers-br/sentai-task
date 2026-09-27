<script lang="ts">
	import { session } from '$lib/api/session.svelte';
	import { confirmationsFor } from '$lib/flow/document';
	import { targetsUsedBy } from '$lib/targets/targets';
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
	/** Typed confirmations by step id; kept across a refused attempt so only the wrong one is retyped. */
	let typed = $state<Record<string, string>>({});
	const confirmation = $derived(confirmationsFor(editor.steps, editor.registry, typed));
	/** Spec 009 FR-009: the targets this flow uses, one password each (never kept). */
	const targets = $derived(targetsUsedBy(editor.steps));
	let targetPasswords = $state<Record<string, string>>({});

	$effect(() => {
		if (open && !dialog.open) {
			message = null;
			typed = {};
			targetPasswords = {};
			dialog.showModal();
		} else if (!open && dialog.open) {
			dialog.close();
		}
	});

	async function onsubmit(event: SubmitEvent) {
		event.preventDefault();
		busy = true;
		const result = await editor.dispatch(password, confirmation.confirmations, targetPasswords);
		busy = false;
		password = '';
		targetPasswords = {};
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
			The run is dispatched under its own sign-in and renews that credential itself for as long as
			it runs, whatever this screen does meanwhile. Your password is used for this sign-in only and
			is not kept.
		</p>

		{#if confirmation.prompts.length > 0}
			<fieldset class="confirmations" data-testid="typed-confirmations">
				<legend>
					<svg width="11" height="11" viewBox="0 0 10 10" aria-hidden="true">
						<path d="M5 0.8 L9.4 8.8 L0.6 8.8 Z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" />
						<path d="M5 3.6 L5 6.2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" />
					</svg>
					{confirmation.prompts.length === 1 ? 'A destructive step needs' : 'Destructive steps need'} a typed confirmation
				</legend>
				{#each confirmation.prompts as prompt (prompt.stepId)}
					<label for={`confirm-${prompt.stepId}`}>
						Type <code>{prompt.expected}</code> to confirm #{prompt.stepId} {prompt.taskName}
					</label>
					<input
						id={`confirm-${prompt.stepId}`}
						type="text"
						required
						autocomplete="off"
						spellcheck="false"
						bind:value={typed[prompt.stepId]}
					/>
				{/each}
			</fieldset>
		{/if}

		<label for="dispatch-password">Password for {session.user}</label>
		<input id="dispatch-password" type="password" autocomplete="current-password" required bind:value={password} />

		{#each targets as target (target)}
			<label for={`dispatch-target-${target}`}>Password for {session.user} on {target}</label>
			<input
				id={`dispatch-target-${target}`}
				type="password"
				autocomplete="off"
				required
				bind:value={targetPasswords[target]}
			/>
		{/each}

		{#if message}<p class="error" role="alert">{message}</p>{/if}

		<div class="actions">
			<button type="button" class="quiet" onclick={() => (open = false)}>Cancel</button>
			<button type="submit" class="primary" disabled={busy || !confirmation.complete}>{busy ? 'Dispatching…' : 'Dispatch'}</button>
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
	.error {
		margin: 0;
		font-size: var(--size-body);
		line-height: 1.5;
	}

	.lead {
		margin-bottom: 8px;
		color: var(--color-text-muted);
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

	.confirmations {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 0 0 8px;
		padding: 10px 12px 12px;
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-accent);
		border-radius: var(--radius-control);
	}

	.confirmations legend {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 0 4px;
		font-size: var(--size-caption);
		font-weight: 600;
		color: var(--destructive-text);
	}

	.confirmations label {
		color: var(--destructive-body-text);
	}

	code {
		font-family: var(--font-mono);
		font-weight: 600;
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
