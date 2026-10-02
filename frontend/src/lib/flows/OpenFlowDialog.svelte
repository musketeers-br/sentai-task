<script lang="ts">
	import { api, describeError } from '$lib/api/client';
	import Modal from '$lib/shell/Modal.svelte';
	import { filterByName, orderBySaved, type FlowSummaryView } from './list';

	// Spec 010 FR-002: every flow the platform returns, most recently saved first, filtered by a
	// case-insensitive name substring, with the open flow marked. Read fresh on every opening —
	// never cached (Key Entities). A refusal is shown exactly as the platform gave it (FR-008).
	// Spec 022 FR-013: the ready-made entry is *Browse runbooks* — it leads to the gallery.
	let {
		open = $bindable(false),
		currentId,
		onpick,
		onnew,
		onbrowse
	}: {
		open: boolean;
		currentId: string | null;
		onpick: (flowId: string) => void;
		onnew: () => void;
		/** Spec 022 FR-013: the ready-made path — the empty-state entry leads to the gallery. */
		onbrowse?: () => void;
	} = $props();

	type State =
		| { name: 'loading' }
		| { name: 'list'; flows: FlowSummaryView[] }
		| { name: 'empty' }
		| { name: 'refused'; message: string };

	let view = $state.raw<State>({ name: 'loading' });
	let filter = $state('');
	const flows = $derived(view.name === 'list' ? view.flows : []);
	const shown = $derived(filterByName(flows, filter));

	$effect(() => {
		if (open) void load();
	});

	async function load() {
		view = { name: 'loading' };
		filter = '';
		const result = await api.listFlows();
		if (!result.ok) view = { name: 'refused', message: describeError(result.error) };
		else if (result.value.length === 0) view = { name: 'empty' };
		else view = { name: 'list', flows: orderBySaved(result.value) };
	}

	function pick(flowId: string) {
		open = false;
		onpick(flowId);
	}

	function startNew() {
		open = false;
		onnew();
	}

	function startBrowse() {
		open = false;
		onbrowse?.();
	}
</script>

<Modal bind:open labelledby="open-flow-title" width="560px">
	<div class="modal-body">
		<h2 id="open-flow-title">Open flow</h2>
		<label for="open-flow-filter">Filter by name</label>
		<!-- svelte-ignore a11y_autofocus -->
		<input id="open-flow-filter" type="search" autocomplete="off" spellcheck="false" autofocus bind:value={filter} />

		{#if view.name === 'loading'}
			<p class="lead" role="status">Reading the saved flows…</p>
		{:else if view.name === 'refused'}
			<p class="error" role="alert">{view.message}</p>
		{:else if view.name === 'empty'}
			<p class="lead">No saved flows yet.</p>
			<div class="actions start">
				{#if onbrowse}
					<button type="button" class="primary" onclick={startBrowse}>Browse runbooks</button>
				{/if}
				<button type="button" class="secondary" onclick={startNew}>New flow</button>
			</div>
		{:else}
			<p class="count" data-testid="flow-count">{shown.length} of {flows.length} flows</p>
			<ul class="rows">
				{#each shown as flow (flow.id)}
					<li>
						<button
							type="button"
							class="row"
							data-testid="flow-row"
							aria-current={flow.id === currentId ? 'true' : undefined}
							onclick={() => pick(flow.id)}
						>
							<span class="name">{flow.name}</span>
							<span class="rev">rev {flow.revision}</span>
							<span class="saved">{flow.savedAt ?? '—'}</span>
						</button>
					</li>
				{/each}
			</ul>
		{/if}

		<div class="actions">
			<button type="button" class="quiet" onclick={() => (open = false)}>Cancel</button>
		</div>
	</div>
</Modal>

<style>
	.count {
		margin: 4px 0 0;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.rows {
		max-height: 360px;
		margin: 0;
		padding: 0;
		overflow-y: auto;
		list-style: none;
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-control);
		/* 5,000 rows (spec 010 T019): let the browser skip layout and paint off-screen. */
		contain: strict;
		height: 360px;
	}

	.rows li {
		content-visibility: auto;
		contain-intrinsic-size: auto 34px;
	}

	.row {
		display: grid;
		grid-template-columns: 1fr auto 150px;
		gap: 12px;
		width: 100%;
		text-align: left;
		color: var(--color-text);
		background: transparent;
		border: 0;
		border-bottom: 1px solid var(--color-border-faint);
		border-radius: 0;
	}

	.row:hover,
	.row:focus-visible {
		background: var(--color-surface);
	}

	.row[aria-current='true'] {
		font-weight: 600;
		box-shadow: inset 3px 0 0 var(--color-text);
	}

	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.rev,
	.saved {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
		white-space: nowrap;
	}

	.start {
		justify-content: flex-start;
	}
</style>
