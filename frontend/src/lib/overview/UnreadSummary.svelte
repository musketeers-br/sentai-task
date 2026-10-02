<script lang="ts">
	import type { UnreadReading } from './attention';

	// Spec 023 FR-029: every reading the Overview could not make, named at the top, so a refused
	// card is never found only by scanning. Hidden only when everything was read.
	let { unread }: { unread: UnreadReading[] } = $props();
</script>

{#if unread.length > 0}
	<section class="unread" data-testid="unread-summary" aria-labelledby="unread-title" role="status">
		<h2 id="unread-title">
			Could not read {unread.length === 1 ? '1 reading' : `${unread.length} readings`} — everything else below is current
		</h2>
		<ul>
			{#each unread as item (item.what)}
				<li><span class="what">{item.what}</span> <span class="line">{item.line}</span></li>
			{/each}
		</ul>
	</section>
{/if}

<style>
	.unread {
		margin: 12px 0 0;
		padding: 10px 12px;
		border: 1px solid var(--color-border);
		border-left: 3px solid var(--state-failed);
		border-radius: var(--radius-control);
		background: var(--color-surface);
	}

	h2 {
		margin: 0 0 6px;
		font-size: var(--size-body);
		font-weight: 600;
	}

	ul {
		display: flex;
		flex-direction: column;
		gap: 3px;
		font-size: var(--size-body);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.what {
		font-weight: 600;
	}

	.line {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}
</style>
