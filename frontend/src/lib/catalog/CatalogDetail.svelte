<script lang="ts">
	import { untrack } from 'svelte';
	import { api } from '$lib/api/client';
	import StateShape from '$lib/design/StateShape.svelte';
	import {
		createSequence,
		DETAIL_FIELDS,
		originMark,
		reduceSuspendAction,
		refusalText,
		statusLabel,
		suspendActionFor,
		type CatalogTaskView,
		type SuspendActionEvent,
		type SuspendActionState,
		type Value
	} from './catalog';
	import CatalogValue from './CatalogValue.svelte';

	// One task as the item read reports it (FR-006, FR-009): every value verbatim, the origin
	// link only when the API says the flow exists, recent runs only when the API sent them.
	let {
		taskParam,
		flowHref,
		onopenflow,
		onchanged,
		onclose
	}: {
		/** The `task` query value, as typed in the address. */
		taskParam: string;
		flowHref: (flowId: string) => string;
		onopenflow: (flowId: string) => void;
		/** The list must be re-read (FR-011). */
		onchanged: () => void;
		onclose: () => void;
	} = $props();

	type Pane =
		| { name: 'loading' }
		| { name: 'ready'; task: CatalogTaskView }
		| { name: 'notFound'; message: string }
		| { name: 'refused'; message: string };

	let pane = $state<Pane>({ name: 'loading' });
	let action = $state<SuspendActionState>({ name: 'idle' });
	const sequence = createSequence();

	$effect(() => {
		const param = taskParam;
		untrack(() => {
			action = { name: 'idle' };
			void load(param);
		});
	});

	/** Applies one step of the suspend/resume state machine and the re-reads it asks for. */
	function apply(event: SuspendActionEvent) {
		const next = reduceSuspendAction(action, event);
		action = next.state;
		if (next.task) pane = { name: 'ready', task: next.task };
		if (next.reread.includes('item')) void load(taskParam, true);
		if (next.reread.includes('list')) onchanged();
	}

	async function setSuspended(task: CatalogTaskView, suspended: boolean) {
		if (action.name === 'pending') return;
		apply({ type: 'send', suspended });
		const result = await api.setSuspended(task.taskId, suspended);
		apply(result.ok ? { type: 'ok', task: result.value } : { type: 'fail', error: result.error });
	}

	/** `quiet`: a re-read after an action keeps the shown task until the answer arrives. */
	async function load(param: string, quiet = false) {
		const n = sequence.next();
		// A non-numeric id cannot name a task: answered here, with no call (api-consumption §2).
		if (!/^\d+$/.test(param)) {
			pane = { name: 'notFound', message: '' };
			return;
		}
		if (!quiet) pane = { name: 'loading' };
		const result = await api.catalogTask(Number(param));
		if (!sequence.isLatest(n)) return;
		if (result.ok) pane = { name: 'ready', task: result.value };
		else if (result.error.kind === 'problem' && result.error.status === 404) pane = { name: 'notFound', message: refusalText(result.error) };
		else pane = { name: 'refused', message: refusalText(result.error) };
	}

	const yesNo = (v: Value<boolean>): Value<string> => (v.kind === 'value' ? { kind: 'value', value: v.value ? 'yes' : 'no' } : v);
	const DESTRUCTIVENESS = { yes: 'destructive', no: 'not destructive', unknown: 'destructiveness unknown' } as const;
</script>

<section class="detail" aria-label="Task detail">
	<header class="head">
		{#if pane.name === 'ready'}
			<div class="title-block">
				<h2 id="detail-title">{pane.task.name}</h2>
				<span class="sub"><CatalogValue value={pane.task.className} /> · ID {pane.task.taskId}</span>
			</div>
		{:else}
			<h2 id="detail-title">Task detail</h2>
		{/if}
		<button type="button" class="quiet" aria-label="Close detail" onclick={onclose}>✕</button>
	</header>

	{#if pane.name === 'loading'}
		<p class="message">Reading the task…</p>
	{:else if pane.name === 'notFound'}
		<p class="message" role="alert">Task not found{pane.message ? ` — ${pane.message}` : ''}</p>
	{:else if pane.name === 'refused'}
		<p class="message" role="alert">{pane.message}</p>
	{:else}
		{@const task = pane.task}
		{@const origin = originMark(task)}
		<div class="marks">
			{#if task.suspended.kind === 'value' && task.suspended.value}
				<span class="mark"><StateShape state="paused" size={11} />SUSPENDED</span>
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
				<span class="mark muted">destructiveness unknown</span>
			{/if}
			{#if origin}
				<span class="mark sentai">SentaiTask</span>
			{/if}
		</div>

		{@const offered = suspendActionFor(task)}
		<div class="actions">
			{#if offered === 'suspend'}
				<button type="button" class="secondary" disabled={action.name === 'pending'} onclick={() => setSuspended(task, true)}>
					{action.name === 'pending' ? 'Suspending…' : 'Suspend'}
				</button>
			{:else if offered === 'resume'}
				<button type="button" class="secondary" disabled={action.name === 'pending'} onclick={() => setSuspended(task, false)}>
					{action.name === 'pending' ? 'Resuming…' : 'Resume'}
				</button>
			{:else if task.suspended.kind === 'unavailable'}
				<span class="note">Suspend/Resume unavailable: HTTP {task.suspended.reason.httpStatus} — {task.suspended.reason.text}</span>
			{/if}
			{#if action.name === 'error'}
				<p class="action-error" role="alert" data-testid="action-error">{action.message}</p>
			{/if}
		</div>

		<dl class="fields">
			{#each DETAIL_FIELDS as field (field.key)}
				<dt>{field.label}</dt>
				<dd data-testid={`detail-field-${field.key}`} class:mono={field.key !== 'name' && field.key !== 'lastError'}>
					{#if field.key === 'name'}
						{task.name}
					{:else if field.key === 'taskId'}
						{task.taskId}
					{:else if field.key === 'namespace'}
						{task.namespace}
					{:else if field.key === 'status'}
						<CatalogValue value={task.status} format={statusLabel} />
					{:else if field.key === 'suspended'}
						<CatalogValue value={yesNo(task.suspended)} />
					{:else if field.key === 'destructive'}
						{DESTRUCTIVENESS[task.destructive]}
					{:else if field.key === 'origin'}
						{#if !origin}
							<span class="none" title="not a SentaiTask task">—</span>
						{:else if origin.flowId !== null}
							{@const flowId = origin.flowId}
							<a
								href={flowHref(flowId)}
								onclick={(e) => {
									e.preventDefault();
									onopenflow(flowId);
								}}>{origin.label}</a
							>
						{:else}
							<span title={origin.title}>{origin.label}</span>
						{/if}
					{:else}
						<CatalogValue value={task[field.key]} />
					{/if}
				</dd>
			{/each}
		</dl>

		{#if task.recentRuns !== undefined}
			<section class="runs" aria-labelledby="runs-title" data-testid="recent-runs">
				<h3 id="runs-title">Recent runs</h3>
				{#if task.recentRuns.length === 0}
					<p class="message">No runs reported</p>
				{:else}
					<table>
						<thead>
							<tr><th>Start</th><th>Completed</th><th>Status</th><th>Result</th><th>User</th><th>Logged</th></tr>
						</thead>
						<tbody>
							{#each task.recentRuns as run, i (i)}
								<tr data-testid="recent-run">
									<td>{run.start}</td><td>{run.completed}</td><td>{run.status}</td><td>{run.result}</td><td>{run.user}</td><td>{run.loggedAt}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				{/if}
			</section>
		{/if}
	{/if}
</section>

<style>
	.detail {
		display: flex;
		flex-direction: column;
		width: 440px;
		flex-shrink: 0;
		min-height: 0;
		overflow: auto;
		background: var(--color-surface);
		border-left: 1px solid var(--color-border);
		color: var(--color-text);
	}

	.head {
		display: flex;
		align-items: flex-start;
		gap: 8px;
		padding: 12px var(--space-section);
		border-bottom: 1px solid var(--color-border-faint);
	}

	.title-block {
		display: flex;
		flex-direction: column;
		gap: 3px;
		min-width: 0;
		flex-grow: 1;
	}

	h2 {
		margin: 0;
		flex-grow: 1;
		font-size: var(--size-title);
		font-weight: 600;
	}

	.sub {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.quiet {
		font: inherit;
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 3px 8px;
		cursor: pointer;
	}

	.message {
		margin: 0;
		padding: 12px var(--space-section);
		font-size: var(--size-body);
		color: var(--color-text-muted);
	}

	.marks {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		padding: 10px var(--space-section) 0;
	}

	.mark,
	.seal {
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
		color: var(--destructive-text);
		background: var(--destructive-surface);
		border-color: var(--destructive-accent);
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px;
		padding: 10px var(--space-section) 0;
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

	.note {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.action-error {
		flex-basis: 100%;
		margin: 0;
		font-size: var(--size-body);
		color: var(--destructive-text);
	}

	.fields {
		display: grid;
		grid-template-columns: 120px minmax(0, 1fr);
		gap: 7px 12px;
		margin: 0;
		padding: 12px var(--space-section);
		font-size: var(--size-body);
	}

	dt {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	dd {
		margin: 0;
		overflow-wrap: anywhere;
	}

	dd :global(.unavailable) {
		white-space: normal;
	}

	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.none {
		color: var(--color-text-faint);
	}

	a {
		color: var(--color-link);
	}

	a:hover {
		color: var(--color-link-hover);
	}

	.runs {
		padding: 0 var(--space-section) 12px;
	}

	h3 {
		margin: 8px 0;
		font-size: var(--size-caption);
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-text-muted);
	}

	.runs .message {
		padding: 0;
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
	}

	th {
		text-align: left;
		font-weight: 600;
		color: var(--color-text-muted);
		border-bottom: 1px solid var(--color-border);
		padding: 4px;
	}

	td {
		border-bottom: 1px solid var(--color-border-faint);
		padding: 4px;
	}
</style>
