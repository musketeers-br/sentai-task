<script lang="ts">
	import StateShape from '$lib/design/StateShape.svelte';
	import ResultPanel from './ResultPanel.svelte';
	import { formatDuration, timeOfDay } from './run';
	import { hasResult } from './result';
	import { buildStepDetail, resultCopyText } from './stepdetail';
	import type { LogEntry, StepRunView } from './run';

	// Spec 016 US2 (plan D-3): one step's execution account in the run view's rail — state,
	// times, duration, where, as whom, the platform's failure reason whole and copyable, and the
	// stored result via 013's ResultPanel (plan D-4: reuse, never a parallel result block).
	let {
		step,
		taskName,
		log,
		nowMs,
		onclose
	}: {
		step: StepRunView;
		taskName: string | undefined;
		log: LogEntry[];
		nowMs: number;
		onclose: () => void;
	} = $props();

	const detail = $derived(buildStepDetail(step, taskName, log, nowMs));
	// The result starts open when the step has one; {#key stepId} in RunScreen remounts per
	// selection, so this is the fresh value, not a stale one.
	// svelte-ignore state_referenced_locally
	let resultOpen = $state(hasResult(step.state, step.result));

	let copied = $state<string | null>(null);
	let copiedTimer: ReturnType<typeof setTimeout> | undefined;
	async function copy(text: string, key: string) {
		try {
			await navigator.clipboard.writeText(text);
			copied = key;
			clearTimeout(copiedTimer);
			copiedTimer = setTimeout(() => (copied = null), 1500);
		} catch {
			// A non-secure origin has no clipboard: the text stays selectable (plan D-7).
		}
	}

	const when = (value: string | null) => (value === null ? '—' : timeOfDay(value));
</script>

<section class="step-detail" aria-label={`Execution detail of #${detail.stepId}`} data-testid="step-detail">
	<header>
		<h2 class="label">STEP DETAIL · #{detail.stepId} {detail.taskName}</h2>
		<button type="button" class="quiet" onclick={onclose} data-testid="close-detail">Close</button>
	</header>

	<dl class="facts">
		<div>
			<dt>STATE</dt>
			<dd data-testid="detail-state"><StateShape state={detail.state} size={11} />{detail.state.toUpperCase()}</dd>
		</div>
		<div>
			<dt>DURATION</dt>
			<dd class="mono">{detail.durationMs === null ? '—' : formatDuration(detail.durationMs)}</dd>
		</div>
		<div>
			<dt>QUEUED</dt>
			<dd class="mono">{when(detail.timeQueued)}</dd>
		</div>
		<div>
			<dt>STARTED</dt>
			<dd class="mono" data-testid="detail-started">{when(detail.timeStarted)}</dd>
		</div>
		<div>
			<dt>FINISHED</dt>
			<dd class="mono">{when(detail.timeFinished)}</dd>
		</div>
		<div>
			<dt>WHERE</dt>
			<!-- FR-011: a step that has not started shows no place, no identity, nothing invented. -->
			<dd class="mono" data-testid="detail-where">
				{detail.executedOn === null
					? '—'
					: `on ${detail.executedOn}${detail.executedAs ? ` · as ${detail.executedAs}` : ''}`}
			</dd>
		</div>
	</dl>

	{#if detail.failureReason}
		<div class="failure" data-testid="failure-block">
			<div class="block-head">
				<span class="label">FAILURE REASON</span>
				<button type="button" class="quiet" onclick={() => copy(detail.failureReason!, 'reason')} data-testid="copy-reason">
					{copied === 'reason' ? 'Copied' : 'Copy'}
				</button>
			</div>
			<!-- Verbatim from IRIS, whole: wrapped, never truncated (SC-002, Constitution III). -->
			<pre data-testid="failure-reason">{detail.failureReason}</pre>
		</div>
	{/if}

	{#if hasResult(detail.state, detail.result)}
		<div class="result-head">
			{#if !resultOpen}
				<button type="button" class="quiet" onclick={() => (resultOpen = true)}>Show result</button>
			{/if}
		</div>
		{#if resultOpen}
			<div class="result-copy">
				<button type="button" class="quiet" onclick={() => copy(resultCopyText(detail.result), 'result')} data-testid="copy-result">
					{copied === 'result' ? 'Copied' : 'Copy result as JSON'}
				</button>
			</div>
			<ResultPanel
				stepId={detail.stepId}
				name={detail.taskName}
				result={detail.result}
				onclose={() => (resultOpen = false)}
			/>
		{/if}
	{/if}
</section>

<style>
	.step-detail {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	header,
	.block-head,
	.result-copy {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
	}

	.label {
		margin: 0;
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.08em;
		color: var(--color-text-muted);
	}

	.facts {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: 8px 14px;
		margin: 0;
	}

	.facts > div {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	dt {
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.08em;
		color: var(--color-text-muted);
	}

	dd {
		margin: 0;
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: var(--size-caption);
	}

	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.failure {
		display: flex;
		flex-direction: column;
		gap: 5px;
		padding: 7px 8px;
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-border);
		border-radius: var(--radius-control);
	}

	.failure pre {
		margin: 0;
		max-height: 140px;
		overflow: auto;
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		line-height: 1.45;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
		color: var(--destructive-body-text);
	}

	.result-head:empty {
		display: none;
	}

	button {
		font: inherit;
		font-size: var(--size-caption);
		padding: 3px 8px;
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		cursor: pointer;
	}

	button:hover {
		color: var(--color-text);
	}

	/* The result panel carries its own card; only the copy row floats above it. */
	.result-copy {
		justify-content: flex-end;
		margin-bottom: -4px;
	}
</style>
