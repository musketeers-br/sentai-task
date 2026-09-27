<script lang="ts">
	import type { Value } from './catalog';

	// One catalog field (data-model.md, the absence rule): the API's value, "unavailable" with the
	// platform's reason (FR-007), or "—" when it reported none or sent nothing. Never filled in.
	let { value, format = (v: string) => v }: { value: Value<string>; format?: (v: string) => string } = $props();
</script>

{#if value.kind === 'unavailable'}
	{@const reason = `HTTP ${value.reason.httpStatus} — ${value.reason.text}`}
	<span class="unavailable" title={reason}>unavailable — {reason}</span>
{:else if value.kind === 'absent'}
	<span class="none" title="not returned">—</span>
{:else if value.value === ''}
	<span class="none" title="none reported">—</span>
{:else}
	{format(value.value)}
{/if}

<style>
	.none {
		color: var(--color-text-faint);
	}

	.unavailable {
		display: inline-block;
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		vertical-align: bottom;
		color: var(--color-text-muted);
		font-style: italic;
	}
</style>
