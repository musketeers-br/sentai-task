<script lang="ts">
	import { untrack } from 'svelte';
	import { api } from '$lib/api/client';
	import StateShape from '$lib/design/StateShape.svelte';
	import {
		catalogQuery,
		createSequence,
		namespaceOptions,
		NO_FILTERS,
		orderByNextRun,
		originMark,
		refusalText,
		statusLabel,
		type CatalogFilters,
		type CatalogPage
	} from './catalog';
	import CatalogDetail from './CatalogDetail.svelte';
	import CatalogValue from './CatalogValue.svelte';

	let {
		taskParam,
		flowHref,
		onselect,
		onopenflow
	}: {
		/** The `task` query value (FR-002): the detail shown, or null for none. */
		taskParam: string | null;
		flowHref: (flowId: string) => string;
		onselect: (taskId: number | null) => void;
		onopenflow: (flowId: string) => void;
	} = $props();

	// The platform's Task Manager as the spec 006 API reports it (US-1, US-3). Rows, counts,
	// filtering and every value come from the API; this screen only orders them for display
	// (FR-004) and re-reads on request (FR-011). There is no background polling.
	type Screen =
		| { name: 'loading' }
		| { name: 'ready'; page: CatalogPage; readAt: number; banner: string | null }
		| { name: 'refused'; message: string };

	const STATES = [
		['all', 'All'],
		['scheduled', 'Scheduled'],
		['suspended', 'Suspended']
	] as const;

	let screen = $state<Screen>({ name: 'loading' });
	let now = $state(Date.now());
	let filters = $state<CatalogFilters>({ ...NO_FILTERS });
	/** Typed text; copied into `filters.q` 300 ms after the last keystroke. */
	let searchText = $state('');
	let namespaces = $state<string[]>(['all']);
	let reading = $state(false);

	const sequence = createSequence();
	const rows = $derived(screen.name === 'ready' ? orderByNextRun(screen.page.items) : []);
	const age = $derived(screen.name === 'ready' ? Math.max(0, Math.round((now - screen.readAt) / 1000)) : 0);

	$effect(() => {
		// A local clock for "updated N s ago" only; it never calls the API.
		const tick = setInterval(() => (now = Date.now()), 1000);
		return () => clearInterval(tick);
	});

	// Every filter change is one API read; the latest request wins. Only the filters are
	// tracked: a token renewal inside the call must not re-read the list (no polling).
	$effect(() => {
		const query = { ...filters };
		untrack(() => void load(query));
	});

	$effect(() => {
		const text = searchText;
		const debounce = setTimeout(() => (filters.q = text), 300);
		return () => clearTimeout(debounce);
	});

	async function load(query: CatalogFilters = { ...filters }) {
		const n = sequence.next();
		reading = true;
		const result = await api.catalogTasks(query);
		if (!sequence.isLatest(n)) return;
		reading = false;
		now = Date.now();
		if (result.ok) {
			if (catalogQuery(query) === '') namespaces = namespaceOptions(result.value);
			screen = { name: 'ready', page: result.value, readAt: now, banner: null };
		} else if (screen.name === 'ready' && result.error.kind === 'problem' && result.error.status === 400) {
			// An invalid filter keeps the previous rows (contracts/api-consumption.md).
			screen = { ...screen, banner: refusalText(result.error) };
		} else {
			screen = { name: 'refused', message: refusalText(result.error) };
		}
	}
</script>

<section class="catalog" aria-labelledby="catalog-title">
	<header class="head">
		<h1 id="catalog-title">Task catalog</h1>
		{#if screen.name === 'ready'}
			<span class="count" data-testid="catalog-count">{screen.page.matched} of {screen.page.total} tasks</span>
		{/if}
		<span class="spacer"></span>
		<button type="button" class="secondary" disabled={reading} onclick={() => load()}>Refresh</button>
	</header>

	<div class="filters">
		<label class="field">
			<span class="field-label">Search tasks</span>
			<input type="search" bind:value={searchText} spellcheck="false" placeholder="name, class or user" />
		</label>
		<label class="field">
			<span class="field-label">Namespace</span>
			<select bind:value={filters.namespace}>
				{#each namespaces as ns (ns)}
					<option value={ns}>{ns === 'all' ? 'All namespaces' : ns}</option>
				{/each}
			</select>
		</label>
		<fieldset class="segmented">
			<legend class="visually-hidden">State</legend>
			{#each STATES as [value, label] (value)}
				<label class:checked={filters.state === value}>
					<input type="radio" name="catalog-state" {value} bind:group={filters.state} />
					{label}
				</label>
			{/each}
		</fieldset>
		<label class="toggle" class:checked={filters.destructiveOnly}>
			<input type="checkbox" bind:checked={filters.destructiveOnly} />
			<svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
				<path d="M5 0.8 L9.4 8.8 L0.6 8.8 Z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" />
				<path d="M5 3.6 L5 6.2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" />
			</svg>
			Destructive only
		</label>
	</div>

	{#if screen.name === 'ready' && screen.banner}
		<p class="banner" role="alert">{screen.banner}</p>
	{/if}

	{#if screen.name === 'loading'}
		<p class="message">Reading the platform's tasks…</p>
	{:else if screen.name === 'refused'}
		<!-- A refused list shows no rows (FR-010); an addressed detail still asks for itself. -->
		<div class="body">
			<p class="message refused" role="alert" data-testid="catalog-refusal">{screen.message}</p>
			{#if taskParam !== null}
				<CatalogDetail {taskParam} {flowHref} {onopenflow} onchanged={() => load()} onclose={() => onselect(null)} />
			{/if}
		</div>
	{:else}
		<div class="body">
		<div class="table-wrap">
			<table>
				<thead>
					<tr>
						<th scope="col">Name</th>
						<th scope="col"><span class="visually-hidden">Marks</span></th>
						<th scope="col">Namespace</th>
						<th scope="col">Class</th>
						<th scope="col">Next run</th>
						<th scope="col">Last run</th>
						<th scope="col">Status</th>
						<th scope="col">Run as</th>
					</tr>
				</thead>
				<tbody>
					{#each rows as task (task.taskId)}
						{@const origin = originMark(task)}
						<tr
							data-testid="catalog-row"
							data-task-id={task.taskId}
							class:selected={taskParam === String(task.taskId)}
							onclick={() => onselect(task.taskId)}
						>
							<td data-col="name">
								<button
									type="button"
									class="row-open"
									aria-current={taskParam === String(task.taskId) ? 'true' : undefined}
									onclick={(e) => {
										e.stopPropagation();
										onselect(task.taskId);
									}}>{task.name}</button
								>
							</td>
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
								{#if origin}
									<span class="mark sentai" data-testid="origin-mark" title={'title' in origin ? origin.title : undefined}>SentaiTask · {origin.label}</span>
								{/if}
							</div></td>
							<td data-col="namespace" class="mono">{task.namespace}</td>
							<td data-col="class" class="mono"><CatalogValue value={task.className} /></td>
							<td data-col="nextRun" class="mono"><CatalogValue value={task.nextRun} /></td>
							<td data-col="lastRun" class="mono"><CatalogValue value={task.lastFinished} /></td>
							<td data-col="status"><CatalogValue value={task.status} format={statusLabel} /></td>
							<td data-col="runAsUser" class="mono"><CatalogValue value={task.runAsUser} /></td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
		{#if taskParam !== null}
			<CatalogDetail {taskParam} {flowHref} {onopenflow} onchanged={() => load()} onclose={() => onselect(null)} />
		{/if}
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

	.filters {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-section);
		padding: 8px var(--space-section);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
		font-size: var(--size-body);
	}

	.field {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.field-label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	input[type='search'],
	select {
		font: inherit;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 5px 8px;
	}

	input[type='search'] {
		width: 240px;
	}

	.segmented {
		display: flex;
		margin: 0;
		padding: 0;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		overflow: hidden;
	}

	.segmented label,
	.toggle {
		position: relative;
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-size: var(--size-caption);
		font-weight: 500;
		color: var(--color-text-muted);
		padding: 6px 10px;
		cursor: pointer;
	}

	.segmented label.checked {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
	}

	.segmented input,
	.toggle input {
		position: absolute;
		inset: 0;
		margin: 0;
		opacity: 0;
		cursor: pointer;
	}

	.segmented label:has(input:focus-visible),
	.toggle:has(input:focus-visible) {
		outline: 2px solid var(--color-focus-ring);
		outline-offset: -2px;
	}

	.toggle {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
	}

	.toggle.checked {
		font-weight: 600;
		color: var(--destructive-text);
		background: var(--destructive-surface);
		border-color: var(--destructive-accent);
	}

	.banner {
		margin: 0;
		padding: 8px var(--space-section);
		font-size: var(--size-body);
		color: var(--destructive-text);
		background: var(--destructive-surface);
		border-bottom: 1px solid var(--destructive-accent);
	}

	.message {
		padding: var(--space-section);
		font-size: var(--size-body);
		color: var(--color-text-muted);
	}

	.refused {
		flex-grow: 1;
		margin: 0;
		color: var(--color-text);
	}

	.body {
		display: flex;
		flex-grow: 1;
		min-height: 0;
	}

	tbody tr {
		cursor: pointer;
	}

	tbody tr:hover {
		background: var(--color-card-raised);
	}

	tr.selected {
		background: var(--color-card-raised);
		box-shadow: inset 3px 0 0 var(--color-text);
	}

	.row-open {
		font: inherit;
		color: inherit;
		background: none;
		border: 0;
		padding: 0;
		text-align: left;
		cursor: pointer;
	}

	.mark.sentai {
		letter-spacing: 0;
		color: var(--color-link);
		border-color: var(--color-link);
	}

	.table-wrap {
		flex-grow: 1;
		min-height: 0;
		overflow: auto;
		background: var(--color-card);
	}

	table {
		width: 100%;
		/* Never squeeze the marks column: with the detail open, the list scrolls sideways. */
		min-width: max-content;
		border-collapse: collapse;
		font-size: var(--size-body);
	}

	td[data-col='marks'] {
		max-width: none;
		overflow: visible;
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
