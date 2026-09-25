<script lang="ts">
	import { onDestroy } from 'svelte';
	import {
		Background,
		BackgroundVariant,
		Controls,
		MiniMap,
		SvelteFlow,
		type Edge,
		type EdgeTypes,
		type NodeTypes
	} from '@xyflow/svelte';
	import '@xyflow/svelte/dist/style.css';
	import FlowEdge from '$lib/canvas/FlowEdge.svelte';
	import StateShape from '$lib/design/StateShape.svelte';
	import type { FlowDocument, StepTypeInfo } from '$lib/flow/document';
	import type { RunFlowNode } from './RunNode.svelte';
	import { autoLayout } from '$lib/flow/layout';
	import Mark from '$lib/shell/Mark.svelte';
	import { RunMonitor, setRunContext } from './monitor.svelte';
	import RunNode from './RunNode.svelte';
	import {
		STEP_STATES,
		countLine,
		formatClock,
		formatDuration,
		isTerminal,
		parseServerTime,
		stepDurationMs,
		timeOfDay
	} from './run';

	let {
		guid,
		flow,
		registry,
		onback
	}: { guid: string; flow: FlowDocument; registry: StepTypeInfo[]; onback: () => void } = $props();

	// svelte-ignore state_referenced_locally
	const monitor = setRunContext(new RunMonitor(guid));
	monitor.start();
	onDestroy(() => monitor.stop());

	// svelte-ignore state_referenced_locally
	const positions = autoLayout(flow.steps.map((s) => s.id), flow.edges, flow.positions);
	// svelte-ignore state_referenced_locally
	let nodes = $state.raw<RunFlowNode[]>(
		flow.steps.map((step) => ({
			id: step.id,
			type: 'run',
			position: positions[step.id],
			data: { step, info: registry.find((r) => r.type === step.type) }
		}))
	);
	// svelte-ignore state_referenced_locally
	let edges = $state.raw<Edge[]>(
		flow.edges.map(({ source, target }) => ({ id: `${source}->${target}`, source, target, type: 'flow' }))
	);
	const nodeTypes: NodeTypes = { run: RunNode };
	const edgeTypes: EdgeTypes = { flow: FlowEdge };

	const run = $derived(monitor.run);
	const steps = $derived(run?.steps ?? []);
	const live = $derived(!!run && !isTerminal(run.state));
	const elapsedMs = $derived.by(() => {
		const start = parseServerTime(run?.startedAt);
		if (start === null) return 0;
		return (parseServerTime(run?.finishedAt) ?? monitor.now) - start;
	});
	const shortGuid = $derived(guid.split('-').slice(0, 4).join('-'));
	const stepName = (stepId: string) => flow.steps.find((s) => s.id === stepId)?.taskName ?? `#${stepId}`;

	let confirmDialog: HTMLDialogElement;
</script>

<div class="run-screen">
	<header class="top-bar">
		<Mark />
		<span class="separator" aria-hidden="true"></span>
		<span class={`pill state-${run?.state ?? 'running'}`} data-testid="run-state">
			<StateShape state={live || !run ? 'running' : run.state} size={9} />
			{live || !run ? 'RUN IN PROGRESS' : `RUN ${run.state.toUpperCase()}`}
		</span>
		<span class="flow-name">{flow.name}</span>
		<span class="faint mono">run {shortGuid}</span>
		<span class="spacer"></span>
		<button type="button" class="quiet" onclick={onback}>Back to flow</button>
		<button type="button" class="pause" disabled={!live || monitor.busy} onclick={() => monitor.pauseRun()}>
			<StateShape state="paused" size={10} /> Pause wave
		</button>
		<button type="button" class="cancel" disabled={!live || monitor.busy} onclick={() => confirmDialog.showModal()}>
			<StateShape state="cancelled" size={11} /> Cancel wave
		</button>
	</header>

	<section class="wave" aria-label="Wave progress">
		<div class="wave-main">
			<div class="wave-head">
				<span class="label">WAVE PROGRESS</span>
				<span class="mono muted" data-testid="count-line">{countLine(steps)}</span>
			</div>
			<div class="segments">
				{#each steps as s (s.stepId)}
					{@const fill = s.state === 'running' && s.progressTotal ? Math.min(1, (s.progressCurrent ?? 0) / s.progressTotal) : null}
					<span
						class={`segment seg-${s.state}`}
						title={`#${s.stepId} ${s.state}`}
						style:--fill={fill === null ? '100%' : `${fill * 100}%`}
					></span>
				{/each}
			</div>
		</div>
		<div class="metric">
			<span class="label">ELAPSED</span>
			<span class="mono big" data-testid="elapsed-clock">{formatClock(elapsedMs)}</span>
		</div>
		<span class="vsep" aria-hidden="true"></span>
		<div class="metric">
			<span class="label">START</span>
			<span class="mono big muted">{timeOfDay(run?.startedAt ?? null)}</span>
		</div>
	</section>

	<div class="body">
		<div class="canvas">
			<SvelteFlow
				bind:nodes
				bind:edges
				{nodeTypes}
				{edgeTypes}
				nodesDraggable={false}
				nodesConnectable={false}
				elementsSelectable={false}
				deleteKey={null}
				fitView
				fitViewOptions={{ padding: 0.15, maxZoom: 1 }}
				proOptions={{ hideAttribution: true }}
			>
				<Background variant={BackgroundVariant.Dots} gap={16} size={1} bgColor="var(--color-ground)" patternColor="var(--color-grid-dot)" />
				<Controls position="bottom-left" orientation="vertical" showLock={false} />
				<MiniMap
					position="bottom-right"
					width={168}
					height={104}
					bgColor="var(--color-surface)"
					maskColor="color-mix(in srgb, var(--color-ground) 55%, transparent)"
					nodeColor={(n) => `var(--state-${monitor.stepFor(n.id)?.state ?? 'queued'})`}
					nodeBorderRadius={0}
					ariaLabel="Minimap"
				/>
			</SvelteFlow>
		</div>

		<aside class="rail" aria-label="Run details">
			<section>
				<h2 class="label">RUN GUIDS</h2>
				<code class="guid" data-testid="run-guid">{guid}</code>
			</section>

			<section>
				<ul class="step-list">
					{#each steps as s (s.stepId)}
						{@const d = stepDurationMs(s, monitor.now)}
						<li class:running={s.state === 'running'}>
							<StateShape state={s.state} size={12} label={s.state} />
							<span class="step-name">#{s.stepId} {stepName(s.stepId)}</span>
							<span class="mono dur">{d === null ? '—' : formatDuration(d)}</span>
						</li>
					{/each}
				</ul>
			</section>

			<section>
				<h2 class="label">STATES — SHAPE BEFORE COLOUR</h2>
				<ul class="key">
					{#each STEP_STATES as s (s)}
						<li style:color={`var(--state-text-${s})`}><StateShape state={s} size={14} />{s}</li>
					{/each}
				</ul>
			</section>

			<section class="log-section">
				<h2 class="label">RUN LOG</h2>
				<div class="log">
					{#each run?.log ?? [] as entry, i (i)}
						<div class={`log-line ${entry.severity}`}>{timeOfDay(entry.at)} · {entry.stepId ? `#${entry.stepId} ` : ''}{entry.message}</div>
					{:else}
						<div class="faint">No log entries recorded for this run.</div>
					{/each}
				</div>
			</section>

			{#if monitor.notice || monitor.error}
				<p class="notice" role="alert">{monitor.notice ?? monitor.error}</p>
			{/if}
		</aside>
	</div>
</div>

<dialog bind:this={confirmDialog} aria-labelledby="cancel-title">
	<form method="dialog">
		<h2 id="cancel-title">Cancel wave?</h2>
		<p>
			Cancel run <strong class="mono">{shortGuid}</strong> of <strong>{flow.name}</strong>. Steps not yet started will
			not be dispatched, and cancellation is requested for running ones.
		</p>
		<div class="actions">
			<button value="keep" class="quiet">Keep running</button>
			<button value="cancel" class="cancel" onclick={() => monitor.cancelRun()}>Cancel wave</button>
		</div>
	</form>
</dialog>

<style>
	.run-screen {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.top-bar,
	.wave {
		display: flex;
		align-items: center;
		flex-shrink: 0;
		box-sizing: border-box;
		padding: 0 var(--space-section);
		border-bottom: 1px solid var(--color-border-faint);
	}

	.top-bar {
		gap: 14px;
		height: var(--chrome-top-bar-height);
		background: var(--color-surface);
	}

	.separator,
	.vsep {
		width: 1px;
		height: 24px;
		background: var(--color-border-faint);
	}

	.pill {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.1em;
		border-radius: var(--radius-chip);
		padding: 3px 7px;
		color: var(--state-text-running);
		border: 1px solid var(--state-running);
	}

	.pill.state-completed {
		color: var(--state-text-completed);
		border-color: var(--state-completed);
	}

	.pill.state-failed {
		color: var(--state-text-failed);
		border-color: var(--state-failed);
	}

	.pill.state-cancelled {
		color: var(--state-text-cancelled);
		border-color: var(--state-cancelled);
	}

	.flow-name {
		font-size: var(--size-bodyStrong);
		font-weight: 600;
	}

	.spacer {
		flex-grow: 1;
	}

	.mono {
		font-family: var(--font-mono);
	}

	.muted {
		color: var(--color-text-muted);
	}

	.faint {
		color: var(--color-text-faint);
		font-size: var(--size-caption);
	}

	button {
		display: inline-flex;
		align-items: center;
		gap: 7px;
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 7px 12px;
		cursor: pointer;
	}

	button:disabled {
		opacity: 0.45;
		cursor: default;
	}

	.quiet {
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
	}

	.pause {
		color: var(--state-text-paused);
		background: var(--warning-surface);
		border: 1px solid var(--warning-border);
	}

	.cancel {
		font-weight: 600;
		color: var(--destructive-text);
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-border);
	}

	.wave {
		gap: 18px;
		height: var(--chrome-wave-progress-height);
		background: var(--color-ground-rail);
	}

	.wave-main {
		display: flex;
		flex-direction: column;
		gap: 5px;
		flex-grow: 1;
	}

	.wave-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		font-size: var(--size-caption);
	}

	.label {
		margin: 0;
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.08em;
		color: var(--color-text-faint);
	}

	.segments {
		display: flex;
		gap: 3px;
		height: 8px;
	}

	.segment {
		flex: 1;
		background: var(--color-border-faint);
	}

	.seg-completed {
		background: var(--state-completed);
	}

	.seg-running {
		background: linear-gradient(90deg, var(--state-running) 0 var(--fill), var(--color-border-faint) var(--fill) 100%);
	}

	.seg-paused {
		background: var(--state-paused);
	}

	/* Hazard stripe, so a failed segment still reads as failed in a monochrome screenshot. */
	.seg-failed {
		background: repeating-linear-gradient(45deg, var(--state-failed) 0 4px, var(--destructive-surface) 4px 8px);
	}

	.seg-cancelled {
		background: repeating-linear-gradient(45deg, var(--state-cancelled) 0 2px, var(--color-border-faint) 2px 6px);
	}

	.metric {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
	}

	.big {
		font-size: var(--size-metric);
		font-weight: 500;
	}

	.body {
		display: flex;
		flex-grow: 1;
		min-height: 0;
	}

	.canvas {
		flex-grow: 1;
		min-width: 0;
	}

	.canvas :global(.svelte-flow__node) {
		padding: 0;
		border: 0;
		background: transparent;
		box-shadow: none;
	}

	.canvas :global(.svelte-flow__controls) {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		overflow: hidden;
		box-shadow: none;
	}

	.canvas :global(.svelte-flow__controls-button) {
		width: 30px;
		height: 30px;
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
		color: var(--color-text);
		fill: var(--color-text);
	}

	.canvas :global(.svelte-flow__minimap) {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
	}

	.rail {
		display: flex;
		flex-direction: column;
		gap: var(--space-loose);
		width: var(--chrome-run-rail-width);
		flex-shrink: 0;
		box-sizing: border-box;
		padding: var(--space-loose);
		background: var(--color-ground-rail);
		border-left: 1px solid var(--color-border-faint);
		overflow-y: auto;
	}

	.rail section {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	.rail section + section {
		border-top: 1px solid var(--color-border-faint);
		padding-top: var(--space-loose);
	}

	.guid {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		word-break: break-all;
		user-select: all;
	}

	ul {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.step-list li {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 3px 0;
		font-size: var(--size-body);
	}

	.step-list li.running {
		font-weight: 700;
	}

	.step-name {
		flex-grow: 1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.dur {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.key {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: 8px;
	}

	.key li {
		display: flex;
		align-items: center;
		gap: 8px;
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.log {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 9px;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
	}

	.log-line.error {
		color: var(--destructive-text);
	}

	.notice {
		margin: 0;
		font-size: var(--size-caption);
		color: var(--destructive-text);
	}

	dialog {
		width: 420px;
		padding: 22px;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--destructive-border);
		border-radius: var(--radius-panel);
	}

	dialog::backdrop {
		background: color-mix(in srgb, var(--color-ground) 70%, transparent);
	}

	dialog h2 {
		margin: 0 0 8px;
		font-size: var(--size-sectionTitle);
	}

	dialog p {
		margin: 0 0 16px;
		font-size: var(--size-body);
		line-height: 1.5;
		color: var(--color-text-muted);
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
	}
</style>
