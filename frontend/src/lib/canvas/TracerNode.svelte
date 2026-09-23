<script lang="ts">
	import { Handle, Position, type NodeProps } from '@xyflow/svelte';
	import type { TracerFlowNode } from './tracer-node-types';

	let { data }: NodeProps<TracerFlowNode> = $props();
</script>

<div class="tracer-node" style:border-left-color={`var(--category-${data.category})`}>
	<Handle type="target" position={Position.Left} />
	<div class="tracer-node__id">#{data.stepId}</div>
	<div class="tracer-node__title">{data.title}</div>
	<Handle type="source" position={Position.Right} />
</div>

<style>
	.tracer-node {
		box-sizing: border-box;
		min-width: 180px;
		padding: var(--space-base) var(--space-snug);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-left-width: 3px;
		border-radius: var(--radius-node);
		color: var(--color-text);
		font-family: var(--font-ui);
	}

	.tracer-node__id {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-faint);
	}

	.tracer-node__title {
		font-size: var(--size-body);
		font-weight: 600;
	}
</style>
