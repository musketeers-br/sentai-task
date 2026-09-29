<script lang="ts">
	import JsonTree from './JsonTree.svelte';

	// Spec 013 FR-012: any stored result, readable without raw JSON. Values are shown as stored.
	let { value, depth = 0 }: { value: unknown; depth?: number } = $props();

	const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);
	const scalar = (v: unknown): string => (v === null || v === undefined ? '—' : String(v));
</script>

{#if Array.isArray(value)}
	{#if value.length === 0}
		<span class="empty">none</span>
	{:else}
		<ol class="list">
			{#each value as item, i (i)}
				<li>
					{#if isObject(item) || Array.isArray(item)}
						<details open={depth < 1 && value.length <= 20}>
							<summary>#{i + 1}</summary>
							<JsonTree value={item} depth={depth + 1} />
						</details>
					{:else}
						<span class="mono">{scalar(item)}</span>
					{/if}
				</li>
			{/each}
		</ol>
	{/if}
{:else if isObject(value)}
	<dl class="obj">
		{#each Object.entries(value) as [key, item] (key)}
			<dt>{key}</dt>
			<dd>
				{#if isObject(item) || Array.isArray(item)}
					<JsonTree value={item} depth={depth + 1} />
				{:else}
					<span class="mono">{scalar(item)}</span>
				{/if}
			</dd>
		{/each}
	</dl>
{:else}
	<span class="mono">{scalar(value)}</span>
{/if}

<style>
	.list {
		margin: 0;
		padding-left: 18px;
	}

	.obj {
		display: grid;
		grid-template-columns: max-content 1fr;
		gap: 2px 10px;
		margin: 0;
	}

	dt {
		color: var(--color-text-muted);
		font-size: var(--size-caption);
	}

	dd {
		margin: 0;
		min-width: 0;
		overflow-wrap: anywhere;
	}

	summary {
		cursor: pointer;
		color: var(--color-text-muted);
		font-size: var(--size-caption);
	}

	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.empty {
		color: var(--color-text-muted);
		font-size: var(--size-caption);
	}
</style>
