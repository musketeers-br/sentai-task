<script lang="ts">
	import type { AttentionView } from './attention';

	// Spec 023 FR-022, FR-026: findings, each with one action. "Nothing needs attention" only when
	// every source was read; what could not be read is said in place.
	let { view, onlink }: { view: AttentionView | null; onlink: (query: string) => void } = $props();
</script>

<section class="band" data-testid="attention-band" aria-labelledby="attention-title">
	<h2 class="label" id="attention-title">
		NEEDS ATTENTION
		{#if view}<span class="sub">{view.items.length === 1 ? '1 item' : `${view.items.length} items`}</span>{/if}
	</h2>
	{#if view === null}
		<p class="faint">Reading…</p>
	{:else}
		{#if view.items.length === 0 && view.missing.length === 0}
			<p class="calm" data-testid="attention-none">Nothing needs attention.</p>
		{/if}
		<ul>
			{#each view.items as item (item.id)}
				<li data-testid={`attention-${item.id}`}>
					<div class="text">
						<span class="title">{item.text}</span>
						<span class="detail">{item.detail}</span>
					</div>
					{#if 'query' in item.action}
						{@const query = item.action.query}
						<button type="button" onclick={() => onlink(query)}>{item.action.label}</button>
					{:else}
						<span class="disabled-action">
							<button type="button" disabled>{item.action.label}</button>
							<span class="reason">{item.action.disabledReason}</span>
						</span>
					{/if}
				</li>
			{/each}
		</ul>
		{#if view.missing.length > 0}
			<p class="missing" data-testid="attention-missing">Not checked: could not read {view.missing.join(', ')}.</p>
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

	ul {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		background: var(--color-card);
	}

	ul:empty {
		display: none;
	}

	li {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 10px 12px;
	}

	li + li {
		border-top: 1px solid var(--color-border-faint);
	}

	.text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		flex-grow: 1;
		min-width: 0;
	}

	.title {
		font-weight: 600;
	}

	.detail,
	.reason,
	.faint,
	.missing,
	.calm {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.detail,
	.reason {
		font-family: var(--font-mono);
	}

	.calm,
	.missing,
	.faint {
		margin: 0;
	}

	.missing {
		margin-top: 6px;
	}

	.disabled-action {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
	}

	button {
		flex-shrink: 0;
		font: inherit;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 5px 10px;
		cursor: pointer;
	}

	button:disabled {
		cursor: default;
		opacity: 0.6;
	}
</style>
