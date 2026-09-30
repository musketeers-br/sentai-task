<script lang="ts">
	import { canSchedule, refusalLine, type AreaCardView } from './overview';

	// Spec 019 US1/US3/US4: one area's card. It shows the API's outcome as it came — headline,
	// refusal verbatim or the transport error — and offers only the actions the API allows.
	let {
		card,
		running,
		onopen,
		onrun,
		onopenreport,
		onschedule,
		onretry
	}: {
		card: AreaCardView;
		running: boolean;
		onopen: () => void;
		onrun: () => void;
		onopenreport: () => void;
		onschedule: () => void;
		onretry: () => void;
	} = $props();

	const dataState = $derived(running ? 'running' : card.state.kind);
</script>

<article class={`card ${card.state.kind}`} data-testid="area-card" data-area={card.area} data-state={dataState} aria-label={card.label}>
	<header>
		<h2>{card.label}</h2>
		<span class="read mono">{card.state.readAt.slice(11, 19)}</span>
	</header>

	{#if card.state.kind === 'ok'}
		{#each card.headlineLines as line, i (i)}
			<p class={i === 0 ? 'headline' : 'sub'}>{line}</p>
		{/each}
	{:else}
		<p class="refusal" data-testid="card-refusal">{refusalLine(card.state)}</p>
	{/if}

	{#if card.report}
		<p class="report-line" data-testid="card-report">
			{#if card.report.state === 'failed'}
				<span class="failed">Report failed</span>
			{:else}
				<span class="sev high">{card.report.counts.high} high</span>
				<span class="sev medium">{card.report.counts.medium} medium</span>
				<span class="sev info">{card.report.counts.info} info</span>
			{/if}
			<span class="faint mono">ran {card.report.ranAt.slice(11, 19)}</span>
		</p>
	{/if}

	<footer>
		{#if card.group === 'instance' && card.state.kind === 'ok'}
			<button type="button" onclick={onopen}>Open</button>
		{/if}
		{#if card.group === 'report'}
			<button type="button" onclick={onrun} disabled={running}>{running ? 'Running…' : 'Run report'}</button>
			{#if card.report}
				<button type="button" class="quiet" onclick={onopenreport}>Open report</button>
			{/if}
		{/if}
		{#if canSchedule(card)}
			<button type="button" class="quiet" onclick={onschedule}>Schedule this check</button>
		{/if}
		{#if card.state.kind === 'unreachable'}
			<button type="button" class="quiet" onclick={onretry}>Retry</button>
		{/if}
	</footer>
</article>

<style>
	.card {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 12px 14px;
		background: var(--color-surface);
		border: 1px solid var(--color-border-faint);
		border-radius: 6px;
		min-height: 128px;
	}

	.card.refused,
	.card.unreachable {
		border-color: var(--color-border);
	}

	header {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 8px;
	}

	h2 {
		margin: 0;
		font-size: var(--size-body);
		font-weight: 600;
	}

	.read,
	.faint {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.mono {
		font-family: var(--font-mono);
	}

	p {
		margin: 0;
	}

	.headline {
		font-size: var(--size-title);
		font-weight: 600;
	}

	.sub {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.refusal {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text);
		overflow-wrap: anywhere;
	}

	.report-line {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		font-size: var(--size-caption);
	}

	.sev,
	.failed {
		font-weight: 600;
	}

	footer {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		margin-top: auto;
		padding-top: 6px;
	}
	button {
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
