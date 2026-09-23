<script lang="ts">
	import Mark from './Mark.svelte';
	import { session } from '$lib/api/session.svelte';

	let { expired = false }: { expired?: boolean } = $props();

	let user = $state(session.user ?? '');
	let password = $state('');
	let message = $state<string | null>(null);
	let busy = $state(false);

	async function onsubmit(event: SubmitEvent) {
		event.preventDefault();
		busy = true;
		const result = await session.login(user, password);
		busy = false;
		password = '';
		// The platform decides who may sign in; its refusal is reported, never reinterpreted.
		message = result.ok ? null : result.message;
	}
</script>

<main class="sign-in">
	<form class="panel" {onsubmit}>
		<Mark />
		<p class="lead">
			{expired
				? 'Your session could not be renewed. Sign in again — your canvas is kept.'
				: 'Sign in with your IRIS credentials.'}
		</p>

		<label for="user">User</label>
		<input id="user" autocomplete="username" required bind:value={user} />

		<label for="password">Password</label>
		<input id="password" type="password" autocomplete="current-password" required bind:value={password} />

		{#if message}<p class="error" role="alert">{message}</p>{/if}

		<button type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
	</form>
</main>

<style>
	.sign-in {
		display: grid;
		place-items: center;
		height: 100%;
		background: var(--color-ground);
	}

	.panel {
		display: flex;
		flex-direction: column;
		gap: 8px;
		width: 320px;
		padding: 28px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: var(--color-card-shadow);
	}

	.lead {
		margin: 12px 0 8px;
		font-size: var(--size-body);
		color: var(--color-text-muted);
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
		margin-bottom: 6px;
	}

	.error {
		margin: 0;
		font-size: var(--size-body);
		color: var(--destructive-text);
	}

	button {
		margin-top: 8px;
		font: inherit;
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 0;
		border-radius: var(--radius-control);
		padding: 9px;
		cursor: pointer;
	}
</style>
