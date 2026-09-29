<script lang="ts">
	import { untrack } from 'svelte';
	import { api, describeError } from '$lib/api/client';
	import StateShape from '$lib/design/StateShape.svelte';
	import type { FlowSummaryView } from '$lib/flows/list';
	import { timeOfDay } from '$lib/run/run';
	import {
		DEFAULT_PAGE_SIZE,
		RUN_STATES,
		countsLine,
		durationText,
		emptyText,
		mergePage,
		nextCursor,
		type RunSummaryView,
		type RunsQuery
	} from './runs';

	// Spec 012 US2: runs, newest first, a page at a time, filtered by flow and outcome. The filters
	// live in the address (FR-007); every refusal is the platform's, verbatim (FR-011).
	let {
		query,
		onquery,
		onopen
	}: {
		query: RunsQuery;
		onquery: (query: RunsQuery) => void;
		onopen: (run: RunSummaryView) => void;
	} = $props();

	type Page =
		| { name: 'loading' }
		| { name: 'ready'; items: RunSummaryView[]; next: number | null; more: boolean }
		| { name: 'refused'; message: string };
	let page = $state<Page>({ name: 'loading' });
	let flows = $state<FlowSummaryView[]>([]);
	const size = $derived(query.pageSize ?? DEFAULT_PAGE_SIZE);

	$effect(() => {
		// Re-read from the first page whenever the filters change.
		void query.flow;
		void query.state;
		untrack(() => void loadFirst());
	});

	$effect(() => {
		untrack(async () => {
			const list = await api.listFlows();
			if (list.ok) flows = [...list.value].sort((a, b) => a.name.localeCompare(b.name));
		});
	});

	async function loadFirst() {
		page = { name: 'loading' };
		const result = await api.listRuns(query, null);
		page = result.ok
			? { name: 'ready', items: result.value, next: nextCursor(result.value, size), more: false }
			: { name: 'refused', message: describeError(result.error) };
	}

	async function loadMore() {
		if (page.name !== 'ready' || page.next === null) return;
		const current = page;
		page = { ...current, more: true };
		const result = await api.listRuns(query, current.next);
		page = result.ok
			? { name: 'ready', items: mergePage(current.items, result.value), next: nextCursor(result.value, size), more: false }
			: { name: 'refused', message: describeError(result.error) };
	}

	const started = (r: RunSummaryView) => (r.startedAt ? `${r.startedAt.slice(0, 10)} ${timeOfDay(r.startedAt)}` : '—');
</script>

<section class="runs" aria-label="Runs">
	<header class="head">
		<h1>Runs</h1>
		{#if page.name === 'ready'}<span class="count" data-testid="runs-count">{page.items.length}{page.next !== null ? '+' : ''} shown</span>{/if}
		<span class="spacer"></span>
		<label for="runs-flow">Flow</label>
		<select
			id="runs-flow"
			value={query.flow ?? ''}
			onchange={(e) => onquery({ ...query, flow: (e.currentTarget as HTMLSelectElement).value || undefined })}
		>
			<option value="">All flows</option>
			{#each flows as f (f.id)}<option value={f.id}>{f.name}</option>{/each}
			{#if query.flow && !flows.some((f) => f.id === query.flow)}<option value={query.flow}>flow {query.flow}</option>{/if}
		</select>
		<label for="runs-state">Outcome</label>
		<select
			id="runs-state"
			value={query.state ?? ''}
			onchange={(e) =>
				onquery({ ...query, state: ((e.currentTarget as HTMLSelectElement).value || undefined) as RunsQuery['state'] })}
		>
			<option value="">Any outcome</option>
			{#each RUN_STATES as s (s)}<option value={s}>{s}</option>{/each}
		</select>
		{#if query.flow || query.state}
			<button type="button" class="quiet" onclick={() => onquery({ pageSize: query.pageSize })}>Clear filters</button>
		{/if}
	</header>

	<div class="table-wrap">
		{#if page.name === 'loading'}
			<p class="state">Loading runs…</p>
		{:else if page.name === 'refused'}
			<p class="state error" role="alert" data-testid="runs-refused">{page.message}</p>
		{:else if page.items.length === 0}
			<p class="state" data-testid="runs-empty">{emptyText(query)}</p>
		{:else}
			<table>
				<thead>
					<tr><th>Flow</th><th>Outcome</th><th>Started</th><th>Duration</th><th>Dispatched by</th><th>Steps</th></tr>
				</thead>
				<tbody>
					{#each page.items as r (r.seq)}
						<tr data-testid="run-row" data-guid={r.guid}>
							<td>
								<button type="button" class="link" onclick={() => onopen(r)}>{r.flowName || `flow ${r.flowId}`}</button>
								<span class="mono faint">rev {r.flowRevision}</span>
							</td>
							<td>
								<span class="outcome" style:color={`var(--state-text-${r.state})`}>
									<StateShape state={r.state} size={11} />{r.state}
								</span>
							</td>
							<td class="mono">{started(r)}</td>
							<td class="mono">{durationText(r.totalDurationMs)}</td>
							<td class="mono">{r.dispatchedBy}</td>
							<td class="mono muted">{countsLine(r.stepCounts)}</td>
						</tr>
					{/each}
				</tbody>
			</table>
			{#if page.next !== null}
				<div class="more">
					<button type="button" class="secondary" disabled={page.more} onclick={loadMore}>
						{page.more ? 'Loading…' : 'Load more'}
					</button>
				</div>
			{/if}
		{/if}
	</div>
</section>

<style>
	.runs {
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
		gap: 10px;
		padding: 10px var(--space-section);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
		font-size: var(--size-body);
	}

	h1 {
		margin: 0 var(--space-section) 0 0;
		font-size: var(--size-title);
		font-weight: 600;
	}

	.count,
	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.count,
	.muted,
	label {
		color: var(--color-text-muted);
	}

	.faint {
		color: var(--color-text-faint, var(--color-text-muted));
		margin-left: 6px;
	}

	.spacer {
		flex-grow: 1;
	}

	select,
	button {
		font: inherit;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 5px 8px;
	}

	button {
		cursor: pointer;
	}

	button.quiet {
		color: var(--color-text-muted);
		background: transparent;
	}

	button.link {
		padding: 0;
		border: 0;
		background: none;
		color: var(--color-text);
		font-weight: 600;
		text-decoration: underline;
		text-underline-offset: 3px;
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
		padding: 8px var(--space-section);
		border-bottom: 1px solid var(--color-border);
	}

	td {
		padding: 8px var(--space-section);
		border-bottom: 1px solid var(--color-border-faint);
		vertical-align: middle;
	}

	.outcome {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.state {
		padding: var(--space-section);
		margin: 0;
		color: var(--color-text-muted);
	}

	.state.error {
		color: var(--destructive-text);
	}

	.more {
		display: flex;
		justify-content: center;
		padding: 12px;
	}
</style>
