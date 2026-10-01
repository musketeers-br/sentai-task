<script lang="ts">
	import { onDestroy, untrack } from 'svelte';
	import { api } from '$lib/api/client';
	import { refusalText } from '$lib/catalog/catalog';
	import {
		areaLabel,
		cellText,
		columnLabel,
		createAutoRefresh,
		rowCountLine,
		visibleRows,
		NO_TABLE_STATE,
		type ReadingState,
		type TableState
	} from './overview';

	// Spec 019 US2: one instance reading as a table — the API's columns, every row it returned,
	// sorted and filtered here only for display. A refused refresh replaces the rows (FR-009).
	// US5: the Processes view offers the platform's own process actions; the platform decides.
	let { area, onback }: { area: string; onback: () => void } = $props();

	let reading = $state<ReadingState>({ kind: 'loading' });
	let table = $state<TableState>({ ...NO_TABLE_STATE });
	let auto = $state(false);
	let actionNotice = $state<string | null>(null);
	let confirming = $state<{ pid: number; typed: string } | null>(null);

	const label = $derived(areaLabel(area));
	const rows = $derived(reading.kind === 'list' ? visibleRows(reading.view, table) : []);

	async function load() {
		const result = await api.overviewReading(area);
		if (result.ok) reading = { kind: 'list', view: result.value };
		else if (result.error.kind === 'network') reading = { kind: 'unreachable', text: result.error.message };
		else reading = { kind: 'refused', text: refusalText(result.error) };
	}

	const refresher = createAutoRefresh({
		intervalMs: 10000,
		read: load,
		isVisible: () => document.visibilityState === 'visible',
		setTimer: (fn, ms) => setTimeout(fn, ms),
		clearTimer: (h) => clearTimeout(h as ReturnType<typeof setTimeout>)
	});

	function onVisibility() {
		refresher.visibilityChanged();
	}

	$effect(() => {
		void area;
		untrack(() => {
			reading = { kind: 'loading' };
			table = { ...NO_TABLE_STATE };
			void load();
		});
	});

	$effect(() => {
		if (auto) refresher.start();
		else refresher.stop();
	});

	$effect(() => {
		document.addEventListener('visibilitychange', onVisibility);
		return () => document.removeEventListener('visibilitychange', onVisibility);
	});

	onDestroy(() => refresher.stop());

	function sort(column: string) {
		table = table.sortBy === column ? { ...table, descending: !table.descending } : { ...table, sortBy: column, descending: false };
	}

	async function act(pid: number, action: 'suspend' | 'resume' | 'terminate', confirmation?: string) {
		actionNotice = null;
		const result = await api.processAction(pid, action, confirmation);
		actionNotice = result.ok ? `${action} ${pid}: HTTP 200` : `${action} ${pid}: ${refusalText(result.error)}`;
		confirming = null;
		await load();
	}
</script>

<section class="reading" aria-label={`${label} reading`}>
	<div class="head">
		<button type="button" class="quiet" onclick={onback}>← Overview</button>
		<h1>{label}</h1>
		{#if reading.kind === 'list'}
			<span class="count mono">{rowCountLine(reading.view.rows.length, rows.length)} · read {reading.view.readAt.slice(11, 19)}</span>
		{/if}
		<span class="spacer"></span>
		<label class="filter">
			<span class="visually-hidden">Filter rows</span>
			<input type="search" placeholder="Filter rows" aria-label="Filter rows" bind:value={table.filter} />
		</label>
		<label class="auto"><input type="checkbox" bind:checked={auto} /> Auto-refresh every 10 s</label>
		<button type="button" onclick={() => void load()}>Refresh</button>
	</div>

	{#if actionNotice}<p class="notice mono" data-testid="process-action-notice">{actionNotice}</p>{/if}

	{#if reading.kind === 'loading'}
		<p class="faint pad">Reading…</p>
	{:else if reading.kind === 'refused' || reading.kind === 'unreachable'}
		<p class="refusal mono pad" data-testid="reading-refusal">{reading.text}</p>
	{:else}
		<div class="scroll">
			<table aria-label={`${label} rows`}>
				<thead>
					<tr>
						{#each reading.view.columns as column (column)}
							<th scope="col" aria-sort={table.sortBy === column ? (table.descending ? 'descending' : 'ascending') : 'none'}>
								<button type="button" class="sort" onclick={() => sort(column)}>
									{columnLabel(column)}{#if reading.view.computed.includes(column)}<span class="computed"> (computed)</span>{/if}
									{#if table.sortBy === column}<span aria-hidden="true">{table.descending ? ' ▾' : ' ▴'}</span>{/if}
								</button>
							</th>
						{/each}
						{#if area === 'processes'}<th scope="col">Actions</th>{/if}
					</tr>
				</thead>
				<tbody>
					{#each rows as row, i (i)}
						<tr>
							{#each reading.view.columns as column (column)}
								<td class={typeof row[column] === 'number' ? 'num' : ''}>{cellText(row[column])}</td>
							{/each}
							{#if area === 'processes' && typeof row.Pid === 'number'}
								{@const pid = row.Pid as number}
								<td class="actions">
									<button type="button" class="quiet" onclick={() => void act(pid, 'suspend')}>Suspend</button>
									<button type="button" class="quiet" onclick={() => void act(pid, 'resume')}>Resume</button>
									<button type="button" class="quiet" onclick={() => (confirming = { pid, typed: '' })}>Terminate</button>
								</td>
							{/if}
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{/if}

	{#if confirming}
		<div class="confirm" role="dialog" aria-label="Terminate process">
			<p>Terminating process <span class="mono">{confirming.pid}</span> ends it on the platform. Type the process id to confirm.</p>
			<input aria-label="Process id to confirm" bind:value={confirming.typed} />
			<div class="row">
				<button type="button" onclick={() => (confirming = null)}>Cancel</button>
				<button type="button" class="danger" disabled={confirming.typed !== String(confirming.pid)} onclick={() => confirming && void act(confirming.pid, 'terminate', confirming.typed)}>
					Terminate
				</button>
			</div>
		</div>
	{/if}
</section>

<style>
	.reading {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
		background: var(--color-ground);
		color: var(--color-text);
	}

	.head {
		display: flex;
		flex-wrap: wrap;
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
	.faint {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.mono {
		font-family: var(--font-mono);
	}

	.spacer {
		flex-grow: 1;
	}

	.auto {
		font-size: var(--size-caption);
		display: flex;
		align-items: center;
		gap: 4px;
	}

	.pad,
	.notice {
		padding: 10px var(--space-section);
		margin: 0;
	}

	.refusal {
		overflow-wrap: anywhere;
	}

	.scroll {
		overflow: auto;
		flex-grow: 1;
	}

	table {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--size-caption);
	}

	th,
	td {
		padding: 4px 10px;
		border-bottom: 1px solid var(--color-border-faint);
		text-align: left;
		white-space: nowrap;
	}

	th {
		position: sticky;
		top: 0;
		background: var(--color-surface);
	}

	.num {
		text-align: right;
		font-family: var(--font-mono);
	}

	button.sort {
		background: none;
		border: none;
		padding: 0;
		font: inherit;
		font-weight: 600;
		color: inherit;
		cursor: pointer;
	}

	.computed {
		font-weight: 400;
		color: var(--color-text-muted);
	}

	.actions {
		display: flex;
		gap: 4px;
	}

	.confirm {
		position: fixed;
		inset: auto 24px 24px auto;
		max-width: 360px;
		padding: 14px;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: 6px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	.confirm p {
		margin: 0;
	}

	.row {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
	}
	button,
	input:not([type='checkbox']) {
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

	button:disabled {
		cursor: default;
		opacity: 0.6;
	}

	button.quiet {
		color: var(--color-text-muted);
		background: transparent;
	}
</style>
