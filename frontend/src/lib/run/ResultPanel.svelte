<script lang="ts">
	import JsonTree from './JsonTree.svelte';
	import { isReport, orderedFindings, severityLabel, summaryLine } from './result';

	// Spec 013 FR-012 (plan D-9): a finished step's stored result, in the run view's side rail.
	// A report shows its findings first, then its details; any other result is shown as a tree.
	let { stepId, name, result, onclose }: { stepId: string; name: string; result: unknown; onclose: () => void } = $props();
	const report = $derived(isReport(result) ? result : null);
</script>

<section class="result-panel" aria-label={`Result of #${stepId}`} data-testid="result-panel">
	<header>
		<h2 class="label">RESULT · #{stepId} {name}</h2>
		<button type="button" class="quiet" onclick={onclose}>Close</button>
	</header>
	{#if report}
		<p class="summary mono" data-testid="report-summary">{summaryLine(report)}{report.instance ? ` · on ${report.instance}` : ''}</p>
		{#if report.findings.length === 0}
			<p class="faint">No findings.</p>
		{:else}
			<ul class="findings" data-testid="report-findings">
				{#each orderedFindings(report) as f, i (i)}
					<li class={`finding ${f.severity}`} data-testid="finding">
						<span class="sev">{severityLabel(f.severity)}</span>
						<span class="rule mono">{f.rule}</span>
						<span class="item">{f.item}</span>
						{#if f.detail}<span class="detail">{f.detail}</span>{/if}
					</li>
				{/each}
			</ul>
		{/if}
		{#if report.summary.findingsOmitted}
			<p class="faint">{report.summary.findingsOmitted} findings did not fit in the stored result.</p>
		{/if}
		<h3 class="label">DETAILS</h3>
		<JsonTree value={report.details} />
		{#if report.truncated}<p class="faint">Shortened to fit: {report.omitted} items left out.</p>{/if}
	{:else}
		<JsonTree value={result} />
	{/if}
</section>

<style>
	.result-panel {
		display: flex;
		flex-direction: column;
		gap: 8px;
		max-height: 420px;
		overflow: auto;
		padding: 10px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
	}

	header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
	}

	h2,
	h3 {
		margin: 0;
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

	.summary {
		margin: 0;
	}

	.findings {
		display: flex;
		flex-direction: column;
		gap: 4px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.finding {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		padding: 5px 7px;
		border-left: 3px solid var(--color-border);
		background: var(--color-surface);
		font-size: var(--size-caption);
	}

	.finding.high {
		border-left-color: var(--destructive-text);
	}

	.finding.medium {
		border-left-color: var(--state-text-paused);
	}

	.sev {
		font-weight: 700;
		min-width: 6ch;
	}

	.detail {
		flex-basis: 100%;
		color: var(--color-text-muted);
		overflow-wrap: anywhere;
	}

	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.faint {
		margin: 0;
		color: var(--color-text-muted);
		font-size: var(--size-caption);
	}
</style>
