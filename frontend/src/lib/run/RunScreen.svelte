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
	import CancelAlertNotice from './CancelAlertNotice.svelte';
	import ResultPanel from './ResultPanel.svelte';
	import StepDetail from './StepDetail.svelte';
	import { cancelRaisesAlert } from './cancel-alert';
	import { chronological, EMPTY_LOG_TEXT, severityLabel } from './log';
	import { buildRunExport, exportFileName } from './export';
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
		onback,
		backLabel = 'Back to flow',
		step = null,
		onselectstep = () => {}
	}: {
		guid: string;
		flow: FlowDocument;
		registry: StepTypeInfo[];
		onback: () => void;
		/** Spec 012 D-7: "Back to runs" when the run was opened from the Runs screen. */
		backLabel?: string;
		/** Spec 016: the addressed step selection (?run=&step=), or null for none. */
		step?: string | null;
		onselectstep?: (stepId: string | null) => void;
	} = $props();

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
	// Spec 011 US5: whether cancelling now ends a running platform job (IRIS then raises an alert).
	const alertOnCancel = $derived(cancelRaisesAlert(steps, flow.steps, registry));
	const stepName = (stepId: string) => flow.steps.find((s) => s.id === stepId)?.taskName ?? `#${stepId}`;

	let confirmDialog: HTMLDialogElement;

	// Spec 016 US2: the selection is addressed (?run=&step=); an id the flow does not have is
	// silently unselected (data-model §5). Node body clicks toggle it; the detail closes it.
	$effect(() => {
		monitor.selectedStepId = step !== null && flow.steps.some((s) => s.id === step) ? step : null;
	});
	const selectFromCanvas = (nodeId: string, event: MouseEvent | TouchEvent) => {
		if ((event.target as HTMLElement).closest('button')) return;
		onselectstep(monitor.selectedStepId === nodeId ? null : nodeId);
	};
	const selected = $derived(
		monitor.selectedStepId !== null ? monitor.stepFor(monitor.selectedStepId) : undefined
	);

	// Spec 012 D-9: oldest first; while live, the newest line stays in view unless the operator
	// scrolled up to read.
	const logLines = $derived(chronological(run?.log ?? []));
	let logBox = $state<HTMLDivElement>();
	let followLog = true;
	function onLogScroll() {
		if (logBox) followLog = logBox.scrollTop + logBox.clientHeight >= logBox.scrollHeight - 8;
	}
	$effect(() => {
		void logLines.length;
		if (live && followLog && logBox) logBox.scrollTop = logBox.scrollHeight;
	});

	// Spec 012 US3: the run as a file, exactly what this view shows (FR-013, FR-014).
	function exportRun() {
		if (!run) return;
		const data = JSON.stringify(buildRunExport(run, flow.name, new Date()), null, 2);
		const url = URL.createObjectURL(new Blob([data], { type: 'application/json' }));
		const a = document.createElement('a');
		a.href = url;
		a.download = exportFileName(flow.name, run.guid);
		a.click();
		setTimeout(() => URL.revokeObjectURL(url), 1000);
	}
</script>

<div class="run-screen">
	<header class="top-bar">
		<Mark />
		<span class="separator" aria-hidden="true"></span>
		<span class={`pill state-${run?.state ?? 'running'}`} data-testid="run-state">
			<StateShape state={live || !run ? 'running' : run.state} size={9} />
			{live || !run ? 'RUN IN PROGRESS' : `RUN ${run.state.toUpperCase()}`}
		</span>
		<h1 class="flow-name">{flow.name}</h1>
		<span class="faint mono">run {shortGuid}</span>
		<span class="spacer"></span>
		<button type="button" class="quiet" onclick={onback}>{backLabel}</button>
		<button type="button" class="quiet" disabled={!run} onclick={exportRun} data-testid="export-run">Export</button>
		<button type="button" class="pause" disabled={!live || monitor.busy} onclick={() => monitor.pauseRun()}>
			<StateShape state="paused" size={10} /> Pause wave
		</button>
		<button type="button" class="cancel" disabled={!live || monitor.busy} onclick={() => confirmDialog.showModal()}>
			<StateShape state="cancelled" size={11} /> Cancel wave
		</button>
	</header>

	<main class="run-main">
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
					onnodeclick={({ node, event }) => selectFromCanvas(String(node.id), event)}
					nodesDraggable={false}
					nodesConnectable={false}
					elementsSelectable={false}
					deleteKey={null}
					fitView
					fitViewOptions={{ padding: 0.15, maxZoom: 1 }}
					proOptions={{ hideAttribution: true }}
				>
					<Background variant={BackgroundVariant.Dots} gap={16} size={1} bgColor="var(--canvas-ground)" patternColor="var(--color-grid-dot)" />
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
							<!-- Spec 016 US2: a row selects its step, like a node click does. -->
							<li class:running={s.state === 'running'}>
								<button
									type="button"
									class="row"
									class:selected={monitor.selectedStepId === s.stepId}
									data-testid="step-row-{s.stepId}"
									onclick={() => onselectstep(s.stepId)}
								>
									<StateShape state={s.state} size={12} label={s.state} />
									<span class="step-name">#{s.stepId} {stepName(s.stepId)}</span>
									<span class="mono dur">{d === null ? '—' : formatDuration(d)}</span>
								</button>
							</li>
						{/each}
					</ul>
				</section>

				{#if selected}
					{@const selectedStep = selected}
					{#key selectedStep.stepId}
						<StepDetail
							step={selectedStep}
							taskName={stepName(selectedStep.stepId)}
							log={run?.log ?? []}
							nowMs={monitor.now}
							onclose={() => onselectstep(null)}
						/>
					{/key}
				{/if}

				{#if monitor.resultFor && monitor.selectedStepId !== monitor.resultFor && monitor.stepFor(monitor.resultFor)}
					{@const shown = monitor.stepFor(monitor.resultFor)!}
					<ResultPanel
						stepId={shown.stepId}
						name={stepName(shown.stepId)}
						result={shown.result}
						onclose={() => (monitor.resultFor = null)}
					/>
				{/if}

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
					<div class="log" bind:this={logBox} onscroll={onLogScroll} data-testid="run-log">
						{#each logLines as entry, i (i)}
							<div class={`log-line ${entry.severity}`} data-testid="log-line">
								<span class="sev">{severityLabel(entry.severity)}</span>
								{timeOfDay(entry.at)} · {entry.message}
							</div>
						{:else}
							<div class="faint">{run ? EMPTY_LOG_TEXT : ''}</div>
						{/each}
					</div>
				</section>

				{#if monitor.notice || monitor.error}
					<p class="notice" role="alert">{monitor.notice ?? monitor.error}</p>
				{/if}
			</aside>
		</div>
	</main>
</div>

<dialog bind:this={confirmDialog} aria-labelledby="cancel-title">
	<form method="dialog">
		<h2 id="cancel-title">Cancel wave?</h2>
		<p>
			Cancel run <strong class="mono">{shortGuid}</strong> of <strong>{flow.name}</strong>. Steps not yet started will
			not be dispatched, and cancellation is requested for running ones.
		</p>
		{#if alertOnCancel}<CancelAlertNotice />{/if}
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
		margin: 0;
		font-size: var(--size-bodyStrong);
		font-weight: 600;
	}

	.run-main {
		display: flex;
		flex-direction: column;
		flex: 1 1 auto;
		min-height: 0;
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
		color: var(--color-text-muted);
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
		color: var(--color-text-muted);
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
		font-size: var(--size-body);
	}

	.step-list .row {
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		padding: 3px 4px;
		font: inherit;
		color: inherit;
		text-align: left;
		background: transparent;
		border: 0;
		cursor: pointer;
		border-radius: var(--radius-control);
	}

	.step-list .row:hover,
	.step-list .row.selected {
		background: var(--color-surface);
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

	.log {
		max-height: 320px;
		overflow: auto;
	}

	.log-line {
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}

	.sev {
		display: inline-block;
		min-width: 5ch;
		font-weight: 700;
	}

	.log-line.warning {
		color: var(--state-text-paused);
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
