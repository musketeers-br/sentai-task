<script lang="ts">
	// Spec 022 US1: one card's mini-graph — pure geometry (miniGraph.ts) rendered as SVG. The
	// graph is decorative detail beside the card's text: the step list carries the same content
	// for a reader, so the svg is aria-hidden.
	import type { MiniGraph as Graph } from './miniGraph';

	let { graph, slug }: { graph: Graph; slug: string } = $props();

	/** A minimap's labels clip to their box; the full names live in the card's step list. */
	const clipped = (label: string) => (label.length > 13 ? `${label.slice(0, 12)}…` : label);
</script>

<svg
	data-testid="runbook-card-graph"
	class="mini"
	viewBox="0 0 {graph.viewBox.width} {graph.viewBox.height}"
	aria-hidden="true"
>
	<defs>
		<marker id="mini-arrow-{slug}" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="5" markerHeight="5" orient="auto">
			<path d="M0,0 L8,4 L0,8 z" />
		</marker>
	</defs>
	{#each graph.edges as edge}
		<line
			data-testid="mini-edge"
			x1={edge.from.x}
			y1={edge.from.y}
			x2={edge.to.x}
			y2={edge.to.y}
			marker-end="url(#mini-arrow-{slug})"
		/>
	{/each}
	{#each graph.nodes as node (node.id)}
		<g>
			<rect
				data-testid="mini-node"
				x={node.x}
				y={node.y}
				width={node.width}
				height={node.height}
				rx="3"
				class:destructive={node.destructive}
			/>
			<text x={node.x + 3} y={node.y + 12.5}>{clipped(node.label)}</text>
		</g>
	{/each}
</svg>

<style>
	.mini {
		display: block;
		width: 100%;
		height: auto;
	}

	.mini line {
		stroke: var(--color-text-muted);
		stroke-width: 1;
	}

	.mini rect {
		fill: var(--color-surface);
		stroke: var(--color-border);
	}

	.mini rect.destructive {
		/* The palette's destructive accent (Palette.svelte): visible on the card (FR-005). */
		stroke: var(--destructive-accent);
	}

	.mini text {
		font-family: var(--font-mono);
		font-size: 7.5px;
		fill: var(--color-text);
	}
</style>
