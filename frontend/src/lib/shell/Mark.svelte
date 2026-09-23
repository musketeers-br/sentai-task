<script lang="ts">
	import { tokens } from '$lib/design/tokens';

	// UI-006 §The mark: five bars — the product's only brand element, never an accent.
	const bars = tokens.mark.bars.map((category, i) => ({ category, height: tokens.mark.heights[i] }));
</script>

<div class="mark">
	<div class="bars" aria-hidden="true">
		{#each bars as bar (bar.category)}
			<span style:height={`${bar.height}px`} style:background={`var(--category-${bar.category})`}></span>
		{/each}
	</div>
	<span class="wordmark">SENTAI<span class="task">TASK</span></span>
</div>

<style>
	.mark {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.bars {
		display: flex;
		align-items: flex-end;
		gap: 2px;
		height: 20px;
	}

	.bars span {
		width: 4px;
	}

	.wordmark {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 16px;
		letter-spacing: 0.06em;
		color: var(--color-text-strong);
	}

	.task {
		font-weight: 500;
		color: var(--color-text-faint);
	}
</style>
