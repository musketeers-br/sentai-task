<script lang="ts">
	import { BaseEdge, getBezierPath, useEdges, type EdgeProps } from '@xyflow/svelte';

	let { id, source, target, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition }: EdgeProps =
		$props();

	// UI-001 §Edges: ≥2 incoming edges converge into ONE diamond per target, drawn once, then a
	// single arrow into the target. Derived from the live edge set, so it never goes stale.
	const edges = useEdges();
	const incoming = $derived(edges.current.filter((e) => e.target === target));
	const isJoin = $derived(incoming.length >= 2);
	const isLead = $derived(
		isJoin && [...incoming].sort((a, b) => a.source.localeCompare(b.source))[0]?.id === id
	);

	const JUNCTION_OFFSET = 34;
	const HALF_DIAMOND = 7;
	const junctionX = $derived(targetX - JUNCTION_OFFSET);

	const path = $derived(
		getBezierPath({
			sourceX,
			sourceY,
			sourcePosition,
			targetX: isJoin ? junctionX - HALF_DIAMOND : targetX,
			targetY,
			targetPosition
		})[0]
	);

	const arrowhead = (x: number, y: number) => `M${x - 7},${y - 4} L${x},${y} L${x - 7},${y + 4} Z`;
</script>

{#if isJoin}
	<BaseEdge {id} {path} class="edge-join" />
	{#if isLead}
		<g class="junction" data-junction-for={target}>
			<path class="join-tail" d={`M${junctionX + HALF_DIAMOND},${targetY} L${targetX - 6},${targetY}`} />
			<path class="join-arrow" d={arrowhead(targetX - 1, targetY)} />
			<rect
				class="junction-diamond"
				x={junctionX - HALF_DIAMOND}
				y={targetY - HALF_DIAMOND}
				width={HALF_DIAMOND * 2}
				height={HALF_DIAMOND * 2}
				transform={`rotate(45 ${junctionX} ${targetY})`}
			/>
		</g>
	{/if}
{:else}
	<BaseEdge {id} {path} class="edge-sequence" />
	<path class="sequence-arrow" d={arrowhead(targetX - 1, targetY)} data-edge-from={source} />
{/if}

<style>
	:global(.svelte-flow__edge-path.edge-sequence) {
		stroke: var(--edge-sequence-color);
		stroke-width: var(--edge-sequence-width);
	}

	:global(.svelte-flow__edge-path.edge-join),
	.join-tail {
		stroke: var(--edge-join-color);
		stroke-width: var(--edge-join-width);
		fill: none;
	}

	.sequence-arrow {
		fill: var(--edge-sequence-color);
	}

	.join-arrow {
		fill: var(--edge-join-color);
	}

	.junction-diamond {
		fill: var(--color-ground);
		stroke: var(--edge-join-color);
		stroke-width: var(--junction-marker-stroke);
	}

	:global(.svelte-flow__edge.selected .svelte-flow__edge-path) {
		stroke: var(--color-focus-ring);
	}
</style>
