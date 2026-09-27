<script lang="ts">
	import { api } from '$lib/api/client';
	import StateShape from '$lib/design/StateShape.svelte';
	import { orderByNextRun, refusalText, statusLabel, type CatalogPage } from './catalog';
	import CatalogValue from './CatalogValue.svelte';

	// The platform's Task Manager as the spec 006 API reports it (US-1). Rows, counts and every
	// value come from the API; this screen only orders them for display (FR-004) and re-reads on
	// request (FR-011). There is no background polling.
	type Screen =
		| { name: 'loading' }
		| { name: 'ready'; page: CatalogPage; readAt: number }
		| { name: 'refused'; message: string };

	let screen = $state<Screen>({ name: 'loading' });
	let now = $state(Date.now());

	const rows = $derived(screen.name === 'ready' ? orderByNextRun(screen.page.items) : []);
	const age = $derived(screen.name === 'ready' ? Math.max(0, Math.round((now - screen.readAt) / 1000)) : 0);

	$effect(() => {
		void load();
		// A local clock for "updated N s ago" only; it never calls the API.
		const tick = setInterval(() => (now = Date.now()), 1000);
		return () => clearInterval(tick);
	});

	async function load() {
		screen = { name: 'loading' };
		const result = await api.catalogTasks();
		now = Date.now();
		screen = result.ok ? { name: 'ready', page: result.value, readAt: now } : { name: 'refused', message: refusalText(result.error) };
	}
</script>

<section class="catalog" aria-labelledby="catalog-title">
	<header class="head">
		<h1 id="catalog-title">Task catalog</h1>
		{#if screen.name === 'ready'}
			<span class="count" data-testid="catalog-count">{screen.page.matched} of {screen.page.total} tasks</span>
		{/if}
		<span class="spacer"></span>
		<button type="button" class="secondary" disabled={screen.name === 'loading'} onclick={load}>Refresh</button>
	</header>

	{#if screen.name === 'loading'}
		<p class="message">Reading the platform's tasks…</p>
	{:else if screen.name === 'refused'}
		<p class="message refused" role="alert" data-testid="catalog-refusal">{screen.message}</p>
	{:else}
		<div class="table-wrap">
			<table>
				<thead>
					<tr>
						<th scope="col">Name</th>
						<th scope="col">Namespace</th>
						<th scope="col">Class</th>
						<th scope="col">Next run</th>
						<th scope="col">Last run</th>
						<th scope="col">Status</th>
						<th scope="col">Run as</th>
						<th scope="col"><span class="visually-hidden">Marks</span></th>
					</tr>
				</thead>
				<tbody>
					{#each rows as task (task.taskId)}
						<tr data-testid="catalog-row" data-task-id={task.taskId}>
							<td data-col="name">{task.name}</td>
							<td data-col="namespace" class="mono">{task.namespace}</td>
							<td data-col="class" class="mono"><CatalogValue value={task.className} /></td>
							<td data-col="nextRun" class="mono"><CatalogValue value={task.nextRun} /></td>
							<td data-col="lastRun" class="mono"><CatalogValue value={task.lastFinished} /></td>
							<td data-col="status"><CatalogValue value={task.status} format={statusLabel} /></td>
							<td data-col="runAsUser" class="mono"><CatalogValue value={task.runAsUser} /></td>
							<td data-col="marks"><div class="marks">
								{#if task.suspended.kind === 'value' && task.suspended.value}
									<span class="mark" data-testid="suspended-mark"><StateShape state="paused" size={11} />SUSPENDED</span>
								{:else if task.suspended.kind === 'unavailable'}
									<span class="mark muted" data-testid="suspended-unavailable" title={`HTTP ${task.suspended.reason.httpStatus} — ${task.suspended.reason.text}`}>suspended: unavailable</span>
								{/if}
								{#if task.destructive === 'yes'}
									<span class="seal" data-testid="destructive-seal">
										<svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
											<path d="M5 0.8 L9.4 8.8 L0.6 8.8 Z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" />
											<path d="M5 3.6 L5 6.2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" />
										</svg>
										DESTRUCTIVE
									</span>
								{:else if task.destructive === 'unknown'}
									<span class="mark muted" data-testid="destructive-unknown">destructiveness unknown</span>
								{/if}
							</div></td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
		<footer class="foot">
			<span>sorted by next run</span>
			<span data-testid="catalog-freshness">updated {age} s ago</span>
		</footer>
	{/if}
</section>

<style>
	.catalog {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
		background: var(--color-ground);
		color: var(--color-text);
	}

	.head {
		display: flex;
		align-items: center;
		gap: var(--space-section);
		padding: 10px var(--space-section);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
	}

	h1 {
		margin: 0;
		font-size: var(--size-title);
		font-weight: 600;
	}

	.count,
	.foot {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.spacer {
		flex-grow: 1;
	}

	.secondary {
		font: inherit;
		font-size: var(--size-body);
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 6px 12px;
		cursor: pointer;
	}

	.secondary:disabled {
		opacity: 0.45;
		cursor: default;
	}

	.message {
		padding: var(--space-section);
		font-size: var(--size-body);
		color: var(--color-text-muted);
	}

	.refused {
		color: var(--color-text);
	}

	.table-wrap {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		background: var(--color-card);
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--size-body);
	}

	th {
		position: sticky;
		top: 0;
		text-align: left;
		font-size: var(--size-micro);
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-text-muted);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
		padding: 9px 10px;
	}

	td {
		max-width: 280px;
		border-bottom: 1px solid var(--color-border-faint);
		padding: 9px 10px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.marks {
		display: flex;
		gap: 6px;
		align-items: center;
	}

	.mark {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.06em;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-chip);
		padding: 2px 6px;
	}

	.mark.muted {
		font-weight: 500;
		letter-spacing: 0;
		color: var(--color-text-muted);
		border-style: dashed;
	}

	.seal {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.08em;
		color: var(--destructive-text);
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-accent);
		border-radius: var(--radius-chip);
		padding: 2px 6px;
	}

	.foot {
		display: flex;
		justify-content: space-between;
		padding: 6px var(--space-section);
		background: var(--color-surface);
		border-top: 1px solid var(--color-border-faint);
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
