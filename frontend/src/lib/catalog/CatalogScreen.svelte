<script lang="ts">
	import { api, describeError } from '$lib/api/client';
	import type { CatalogPage } from './catalog';

	type State =
		| { name: 'loading' }
		| { name: 'ready'; page: CatalogPage }
		| { name: 'refused'; message: string };

	let state = $state<State>({ name: 'loading' });

	$effect(() => {
		void load();
	});

	async function load() {
		state = { name: 'loading' };
		const result = await api.catalogTasks();
		state = result.ok ? { name: 'ready', page: result.value } : { name: 'refused', message: describeError(result.error) };
	}
</script>

<section class="catalog" aria-labelledby="catalog-title">
	<h1 id="catalog-title">Task catalog</h1>

	{#if state.name === 'loading'}
		<p class="message">Reading the platform's tasks…</p>
	{:else if state.name === 'refused'}
		<p class="message" role="alert">{state.message}</p>
	{:else}
		<table>
			<thead>
				<tr><th scope="col">Name</th><th scope="col">Namespace</th></tr>
			</thead>
			<tbody>
				{#each state.page.items as task (task.taskId)}
					<tr><td>{task.name}</td><td class="mono">{task.namespace}</td></tr>
				{/each}
			</tbody>
		</table>
	{/if}
</section>

<style>
	.catalog {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		padding: var(--space-section);
		background: var(--color-ground);
		color: var(--color-text);
	}

	h1 {
		margin: 0 0 var(--space-section);
		font-size: var(--size-bodyStrong);
		font-weight: 600;
	}

	.message {
		font-size: var(--size-body);
		color: var(--color-text-muted);
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--size-body);
	}

	th {
		text-align: left;
		font-size: var(--size-caption);
		font-weight: 600;
		color: var(--color-text-muted);
		border-bottom: 1px solid var(--color-border);
		padding: 6px 8px;
	}

	td {
		border-bottom: 1px solid var(--color-border-faint);
		padding: 6px 8px;
	}

	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}
</style>
