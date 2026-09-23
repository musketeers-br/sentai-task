<script lang="ts">
	import { SvelteFlow, Background, type NodeTypes, type Edge } from '@xyflow/svelte';
	import '@xyflow/svelte/dist/style.css';
	import TracerNode from './TracerNode.svelte';
	import type { TracerFlowNode } from './tracer-node-types';
	import { tracerNodes, tracerEdges } from '$lib/fixtures/tracer-graph';
	import { tokens } from '$lib/design/tokens';

	// Tracer bullet renders the dark theme's tokens only (research.md: theme switch deferred).
	const theme = tokens.theme.dark;

	const nodeTypes: NodeTypes = { tracer: TracerNode };

	let nodes = $state.raw<TracerFlowNode[]>(
		tracerNodes.map((n, i) => ({
			id: n.id,
			type: 'tracer',
			position: { x: i * 260, y: 0 },
			data: { stepId: n.id, title: n.title, category: n.category }
		}))
	);

	// Exactly one edge, rendered as a sequence edge (edge.sequence token: 1.5px, arrowhead) —
	// never a join, per data-model.md (a fan-in needs ≥2 incoming edges on one target).
	let edges = $state.raw<Edge[]>(
		tracerEdges.map((e) => ({
			id: `${e.source}->${e.target}`,
			source: e.source,
			target: e.target,
			type: 'default',
			markerEnd: { type: 'arrowclosed', color: tokens.edge.sequence.dark }
		}))
	);
</script>

<div class="tracer-canvas">
	<SvelteFlow bind:nodes bind:edges {nodeTypes} fitView colorMode="dark">
		<Background bgColor={theme.ground} patternColor={theme.gridDot} />
	</SvelteFlow>
</div>

<style>
	.tracer-canvas {
		width: 100%;
		height: 100%;
	}

	/* Sequence edge treatment (UI-006): 1.5px, muted token, arrowhead. Applied globally so every
	   sequence edge shares the same look, rather than repeating the token inline per edge. */
	:global(.svelte-flow__edge-path) {
		stroke: var(--edge-sequence-color);
		stroke-width: var(--edge-sequence-width);
	}
</style>
