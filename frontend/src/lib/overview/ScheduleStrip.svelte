<script lang="ts">
	import type { StripResult } from './attention';

	// Spec 023 FR-023: what the Task Manager runs in the next 24 hours, by half hour, on the
	// instance clock. A read that failed is said in place, never drawn as an empty day.
	let { result, unreadLine }: { result: StripResult | null; unreadLine: string | null } = $props();
</script>

<section class="band" data-testid="schedule-strip" aria-labelledby="schedule-title">
	<h2 class="label" id="schedule-title">
		NEXT 24 HOURS
		{#if result?.kind === 'ready'}
			<span class="sub" data-testid="schedule-summary">
				{result.strip.total === 1 ? '1 task' : `${result.strip.total} tasks`} · {result.strip.destructive} destructive · {result.strip.flowScheduled
					? 'a flow is scheduled'
					: 'no flow scheduled'}
			</span>
		{/if}
	</h2>
	{#if unreadLine !== null}
		<p class="missing" data-testid="schedule-unread">Could not read the task catalog: {unreadLine}</p>
	{:else if result === null}
		<p class="faint">Reading…</p>
	{:else if result.kind === 'unread'}
		<p class="missing" data-testid="schedule-unread">Cannot place the schedule: {result.why}.</p>
	{:else}
		{#if result.strip.slots.length === 0}
			<p class="faint" data-testid="schedule-empty">Nothing scheduled in the next 24 hours.</p>
		{:else}
			<ol class="strip">
				{#each result.strip.slots as slot (slot.start)}
					<li data-testid="schedule-slot" data-start={slot.start}>
						<span class="time">{slot.start}</span>
						<span class="count">{slot.count}</span>
						{#if slot.destructive > 0}<span class="mark destructive">{slot.destructive} destructive</span>{/if}
						{#if slot.suspended > 0}<span class="mark">{slot.suspended} susp.</span>{/if}
					</li>
				{/each}
			</ol>
		{/if}
		{#if result.strip.nextAfter}
			<p class="faint after">then nothing until <span class="mono">{result.strip.nextAfter}</span></p>
		{/if}
	{/if}
</section>

<style>
	.label {
		display: flex;
		align-items: baseline;
		gap: 8px;
		margin: 16px 0 8px;
		font-size: var(--size-caption);
		font-weight: 600;
		letter-spacing: 0.06em;
		color: var(--color-text-muted);
	}

	.sub {
		font-weight: 500;
		letter-spacing: 0;
	}

	.strip {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	li {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 76px;
		padding: 8px 10px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		background: var(--color-card);
	}

	.time,
	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.count {
		font-size: var(--size-title);
		font-weight: 600;
	}

	.mark {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		color: var(--color-text-muted);
	}

	.mark.destructive {
		color: var(--destructive-text);
	}

	.faint,
	.missing {
		margin: 0;
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.after {
		margin-top: 6px;
	}
</style>
