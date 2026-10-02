<script lang="ts">
	import { untrack } from 'svelte';
	import { api } from '$lib/api/client';
	import StateShape from '$lib/design/StateShape.svelte';
	import type { StepTypeInfo } from '$lib/flow/document';
	import Modal from '$lib/shell/Modal.svelte';
	import {
		createSequence,
		destructiveReason,
		DETAIL_FIELDS,
		originMark,
		outsideMark,
		reduceSuspendAction,
		refusalText,
		statusLabel,
		stepFromTask,
		suspendToggle,
		type CatalogTaskView,
		type StepDraft,
		type SuspendActionEvent,
		type SuspendActionState,
		type Value
	} from './catalog';
	import CatalogValue from './CatalogValue.svelte';

	// One task as the item read reports it (FR-006, FR-009): every value verbatim, the origin
	// link only when the API says the flow exists, recent runs only when the API sent them.
	let {
		taskParam,
		registry,
		flowHref,
		onopenflow,
		onaddtoflow,
		onchanged,
		onclose
	}: {
		/** The `task` query value, as typed in the address. */
		taskParam: string;
		/** Spec 023: the step-type catalog, for the destructive reason and Add to a flow. */
		registry: StepTypeInfo[];
		flowHref: (flowId: string) => string;
		onopenflow: (flowId: string) => void;
		/** Spec 023 FR-018: put this task's step type on the open flow. */
		onaddtoflow: (step: StepDraft) => void;
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

	// Spec 023 FR-020: the toggle asks first; only Confirm sends the spec 007 call.
	let confirmOpen = $state(false);

	function toggle(task: CatalogTaskView) {
		const checked = suspendToggle(task).checked;
		if (checked === null || action.name === 'pending') return;
		apply({ type: 'toggle', suspended: !checked });
		confirmOpen = action.name === 'confirming';
	}

	async function confirmToggle(task: CatalogTaskView) {
		if (action.name !== 'confirming') return;
		const suspended = action.suspended;
		apply({ type: 'confirm' });
		confirmOpen = false;
		const result = await api.setSuspended(task.taskId, suspended);
		apply(result.ok ? { type: 'ok', task: result.value } : { type: 'fail', error: result.error });
	}

	/** Every way the confirmation closes without Confirm (Cancel, Escape) sends nothing. */
	function onconfirmclose() {
		if (action.name === 'confirming') apply({ type: 'cancel' });
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
			{:else if outsideMark(task)}
				<span class="mark muted" data-testid="outside-mark">created outside SentaiTask</span>
			{/if}
		</div>

		{@const draft = stepFromTask(task, registry)}
		{@const toggleView = suspendToggle(task)}
		<div class="actions">
			<button
				type="button"
				class="primary"
				disabled={!draft.ok}
				data-testid="add-to-flow"
				onclick={() => draft.ok && onaddtoflow(draft.step)}
			>
				Add to a flow
			</button>
			{#if !draft.ok}<span class="note" data-testid="add-to-flow-reason">{draft.reason}</span>{/if}
			<span class="spacer"></span>
			<label class="switch" class:on={toggleView.checked === true}>
				<input
					type="checkbox"
					role="switch"
					checked={toggleView.checked === true}
					aria-checked={toggleView.checked === true}
					disabled={toggleView.checked === null || action.name === 'pending'}
					onclick={(e) => {
						e.preventDefault();
						toggle(task);
					}}
				/>
				<span class="track" aria-hidden="true"><span class="thumb"></span></span>
				{action.name === 'pending' ? (action.suspended ? 'Suspending…' : 'Resuming…') : 'Suspended'}
			</label>
			{#if task.suspended.kind === 'unavailable'}
				<span class="note">Suspend/Resume unavailable: HTTP {task.suspended.reason.httpStatus} — {task.suspended.reason.text}</span>
			{/if}
			{#if action.name === 'error'}
				<p class="action-error" role="alert" data-testid="action-error">{action.message}</p>
			{/if}
		</div>

		{@const reason = destructiveReason(task, registry)}
		{#if reason}
			<section class="why" data-testid="destructive-reason" aria-labelledby="why-title">
				<h3 id="why-title">Why this is destructive</h3>
				{#if reason.kind === 'stepType'}
					<p>{reason.text}</p>
				{:else}
					{@const flowId = reason.flowId}
					<p>
						Destructive because
						<a
							href={flowHref(flowId)}
							onclick={(e) => {
								e.preventDefault();
								onopenflow(flowId);
							}}>flow {flowId}</a
						> contains a destructive step.
					</p>
				{/if}
				<p class="note">classified from the step-type registry · not editable here</p>
			</section>
		{/if}

		<Modal bind:open={confirmOpen} labelledby="suspend-confirm-title" describedby="suspend-confirm-body" onclose={onconfirmclose}>
			<div class="confirm">
				<h2 id="suspend-confirm-title">{toggleView.confirm.title}</h2>
				<p id="suspend-confirm-body">{toggleView.confirm.body}</p>
				<div class="confirm-actions">
					<button type="button" class="quiet" onclick={() => (confirmOpen = false)}>Cancel</button>
					<button type="button" class="primary" onclick={() => void confirmToggle(task)}>
						{toggleView.confirm.action === 'suspend' ? 'Suspend' : 'Resume'}
					</button>
				</div>
			</div>
		</Modal>

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
					<p class="message">No run recorded. This task has never executed on this instance.</p>
				{:else}
					<table>
						<thead>
							<tr><th>Start</th><th>Completed</th><th>Status</th><th>Result</th><th>User</th><th>Logged</th></tr>
						</thead>
						<tbody>
							{#each task.recentRuns.slice(0, 5) as run, i (i)}
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

	.primary:disabled {
		opacity: 0.45;
		cursor: default;
	}

	.primary {
		font: inherit;
		font-size: var(--size-body);
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
		border-radius: var(--radius-control);
		padding: 6px 12px;
		cursor: pointer;
	}

	.spacer {
		flex-grow: 1;
	}

	.switch {
		position: relative;
		display: inline-flex;
		align-items: center;
		gap: 7px;
		font-size: var(--size-body);
		cursor: pointer;
	}

	/* The real control covers the whole switch, so a click anywhere on it reaches the input. */
	.switch input {
		position: absolute;
		inset: 0;
		z-index: 1;
		margin: 0;
		opacity: 0;
		cursor: inherit;
	}

	.track {
		position: relative;
		width: 30px;
		height: 16px;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		background: var(--color-card);
	}

	.thumb {
		position: absolute;
		top: 2px;
		left: 2px;
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--color-text-muted);
		transition: left 120ms;
	}

	.switch.on .track {
		background: var(--color-text);
		border-color: var(--color-text);
	}

	.switch.on .thumb {
		left: 16px;
		background: var(--color-ground);
	}

	.switch input:focus-visible + .track {
		outline: 2px solid var(--color-focus-ring);
		outline-offset: 2px;
	}

	.switch:has(input:disabled) {
		opacity: 0.45;
		cursor: default;
	}

	.why {
		margin: 10px var(--space-section) 0;
		padding: 10px 12px;
		border: 1px solid var(--destructive-accent);
		border-radius: var(--radius-control);
		background: var(--destructive-surface);
	}

	.why h3 {
		margin-top: 0;
		color: var(--destructive-text);
	}

	.why p {
		margin: 0 0 6px;
		font-size: var(--size-body);
		line-height: 1.5;
	}

	.confirm {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 20px;
		max-width: 420px;
	}

	.confirm p {
		margin: 0;
		font-size: var(--size-body);
		line-height: 1.5;
		color: var(--color-text-muted);
	}

	/* The dialog sits in the top layer, outside this panel: sizes are set, not inherited. */
	.confirm-actions button {
		font-size: var(--size-body);
		padding: 6px 12px;
	}

	.confirm-actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
		margin-top: 6px;
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
		color: var(--color-text-muted);
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
