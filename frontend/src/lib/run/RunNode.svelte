<script lang="ts" module>
	import type { Node } from '@xyflow/svelte';
	import type { StepNodeData } from '$lib/flow/editor.svelte';

	export type RunFlowNode = Node<StepNodeData, 'run'>;
</script>

<script lang="ts">
	import { Handle, Position, useNodeConnections, type NodeProps } from '@xyflow/svelte';
	import StateShape from '$lib/design/StateShape.svelte';
	import { getRunContext } from './monitor.svelte';
	import { formatDuration, isTerminal, stepDurationMs, timeOfDay } from './run';

	let { id, data }: NodeProps<RunFlowNode> = $props();

	const monitor = getRunContext()!;
	const incoming = useNodeConnections({ handleType: 'target' });

	const step = $derived(data.step);
	const category = $derived(data.info?.category ?? 'custom');
	const destructive = $derived(data.info?.destructive === true);
	const sr = $derived(monitor.stepFor(id));
	const state = $derived(sr?.state ?? 'queued');
	const duration = $derived(sr ? stepDurationMs(sr, monitor.now) : null);
	const sources = $derived(incoming.current.map((c) => c.source).sort());
	const waitingFor = $derived(sources.filter((s) => monitor.stepFor(s)?.state !== 'completed'));
	const failedInputs = $derived(
		sources.filter((s) => ['failed', 'cancelled'].includes(monitor.stepFor(s)?.state ?? ''))
	);
	const progress = $derived(
		sr?.progressTotal ? Math.min(1, (sr.progressCurrent ?? 0) / sr.progressTotal) : null
	);
	// IRIS GUIDs are time-based: steps created together share the tail (node id) and the first
	// few characters, so the distinguishing part is the first group.
	const shortGuid = $derived(sr ? `${sr.guid.split('-')[0]}…` : '');
	// The backend only picks a re-run up while the run's loop is alive (HANDOFF 003, 2026-09-25).
	const runLive = $derived(!!monitor.run && !isTerminal(monitor.run.state));
</script>

<article
	class={`node state-${state}`}
	style:--node-category={`var(--category-${category})`}
	style:--state-color={`var(--state-${state})`}
	style:--state-text={`var(--state-text-${state})`}
	data-step-id={id}
	data-state={state}
>
	{#if destructive}<div class="hazard-band" aria-hidden="true"></div>{/if}
	<div class="body">
		<header class="title-row">
			<h3 class="title">{step.taskName}</h3>
			<span class="state-chip" data-testid="state-chip">
				<StateShape {state} size={11} />
				{state.toUpperCase()}
			</span>
		</header>
		<div class="muted mono">
			{step.namespace}{step.databaseDirectory ? ` · ${step.databaseDirectory}` : ''} · #{id}
		</div>

		{#if state === 'running'}
			<div class="elapsed" data-testid="elapsed">{duration === null ? '—' : formatDuration(duration)}</div>
			{#if progress !== null}
				<div class="progress" role="progressbar" aria-valuenow={Math.round(progress * 100)} aria-valuemin="0" aria-valuemax="100">
					<span style:width={`${progress * 100}%`}></span>
				</div>
				<div class="muted mono">{sr?.progressCurrent} of {sr?.progressTotal}</div>
			{/if}
		{/if}

		{#if state === 'failed' && sr?.failureReason}
			<div class="failure" data-testid="failure-reason">
				<div class="failure-title">FAILURE REASON</div>
				<!-- Verbatim from IRIS (FR-026): never summarised, cased or truncated. -->
				<pre>{sr.failureReason}</pre>
			</div>
		{/if}

		{#if failedInputs.length > 0}
			<div class="join-policy" data-testid="join-policy">
				<div class="join-policy-title">JOIN POLICY</div>
				<div>
					All inputs must succeed — {failedInputs.map((s) => `#${s}`).join(' ')} did not complete, so
					#{id} does not start.
				</div>
			</div>
		{/if}

		<div class="divider"></div>
		<footer class="footer">
			{#if state === 'queued'}
				<span>{waitingFor.length ? `waits for ${waitingFor.map((s) => `#${s}`).join(' ')}` : `queued since ${timeOfDay(sr?.timeQueued ?? null)}`}</span>
			{:else if state === 'running'}
				<span class="mono" title={sr?.guid}>GUID {shortGuid}</span>
				<button type="button" class="action danger" disabled={monitor.busy} onclick={() => sr && monitor.cancelStep(sr.guid)}
					title="Stops SentaiTask tracking this step; in v1 the platform job is not cancelled">Cancel</button>
			{:else if state === 'failed'}
				<span class="mono">failed at {duration === null ? '—' : formatDuration(duration)}</span>
				{#if runLive}
					<button type="button" class="action" disabled={monitor.busy} onclick={() => sr && monitor.rerunStep(sr.guid)}>Re-run step</button>
				{/if}
			{:else}
				<span class="mono">{duration === null ? '—' : formatDuration(duration)}</span>
				<span class="mono" title={sr?.guid}>GUID {shortGuid}</span>
			{/if}
		</footer>
	</div>
	<Handle type="target" position={Position.Left} isConnectable={false} class="handle" />
	<Handle type="source" position={Position.Right} isConnectable={false} class="handle" />
</article>

<style>
	.node {
		position: relative;
		box-sizing: border-box;
		width: 260px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-left: 3px solid var(--node-category);
		border-radius: var(--radius-node);
		box-shadow: var(--color-card-shadow);
		color: var(--color-text);
		font-family: var(--font-ui);
	}

	.node.state-running {
		border-color: var(--state-running);
		border-left-color: var(--node-category);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--state-running) 25%, transparent);
	}

	.node.state-failed {
		border-color: var(--state-failed);
		border-left-color: var(--node-category);
	}

	.node.state-queued {
		border-style: dashed;
		border-left-style: solid;
	}

	.hazard-band {
		height: var(--destructive-hazard-height);
		border-top-right-radius: calc(var(--radius-node) - 1px);
		background: repeating-linear-gradient(
			var(--destructive-hazard-angle),
			var(--destructive-accent) 0 var(--destructive-hazard-stripe),
			var(--color-card) var(--destructive-hazard-stripe) calc(var(--destructive-hazard-stripe) * 2)
		);
	}

	.body {
		display: flex;
		flex-direction: column;
		gap: var(--space-snug);
		padding: var(--space-base) 11px;
	}

	.title-row {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 8px;
	}

	.title {
		margin: 0;
		font-size: var(--size-bodyStrong);
		font-weight: 600;
		color: var(--color-text-strong);
	}

	.state-chip {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		flex-shrink: 0;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.08em;
		color: var(--state-text);
		border: 1px solid var(--state-color);
		border-radius: var(--radius-chip);
		padding: 2px 6px;
	}

	.mono,
	.footer {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
	}

	.muted {
		color: var(--color-text-muted);
	}

	.elapsed {
		font-family: var(--font-mono);
		font-size: var(--size-metric);
		font-weight: 500;
		color: var(--color-text-strong);
	}

	.progress {
		height: 5px;
		background: var(--color-border-faint);
		border-radius: 2px;
		overflow: hidden;
	}

	.progress span {
		display: block;
		height: 100%;
		background: var(--state-running);
	}

	.failure {
		padding: 7px 8px;
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-border);
		border-radius: var(--radius-control);
	}

	.failure-title,
	.join-policy-title {
		font-size: var(--size-micro);
		font-weight: 700;
		letter-spacing: 0.08em;
	}

	.failure-title {
		color: var(--destructive-text);
	}

	.failure pre {
		margin: 3px 0 0;
		max-height: 120px;
		overflow: auto;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		line-height: 1.45;
		white-space: pre-wrap;
		word-break: break-word;
		color: var(--destructive-body-text);
	}

	.join-policy {
		padding: 7px 8px;
		font-size: var(--size-micro);
		line-height: 1.45;
		color: var(--color-text);
		background: var(--color-surface);
		border: 1px solid var(--color-border-strong);
		border-radius: var(--radius-control);
	}

	.join-policy-title {
		color: var(--color-text-muted);
	}

	.divider {
		height: 1px;
		background: var(--color-border-faint);
	}

	.footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		color: var(--color-text-muted);
	}

	.action {
		font-family: var(--font-ui);
		font-size: var(--size-caption);
		font-weight: 600;
		color: var(--color-text);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 4px 9px;
		cursor: pointer;
	}

	.action.danger {
		color: var(--destructive-text);
		border-color: var(--destructive-border);
		background: var(--destructive-surface);
	}

	.action:disabled {
		opacity: 0.5;
		cursor: default;
	}

	.node :global(.handle) {
		width: var(--handle-plain-size);
		height: var(--handle-plain-size);
		min-width: 0;
		min-height: 0;
		background: var(--canvas-ground);
		border: var(--handle-plain-stroke) solid var(--color-border-strong);
		border-radius: var(--handle-plain-radius);
	}
</style>
