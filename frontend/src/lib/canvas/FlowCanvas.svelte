<script lang="ts">
	import {
		Background,
		BackgroundVariant,
		Controls,
		MiniMap,
		Panel,
		SvelteFlow,
		useSvelteFlow,
		type Connection,
		type Edge,
		type EdgeTypes,
		type NodeTypes
	} from '@xyflow/svelte';
	import '@xyflow/svelte/dist/style.css';
	import StepNode from './StepNode.svelte';
	import FlowEdge from './FlowEdge.svelte';
	import type { FlowEditor, StepFlowNode } from '$lib/flow/editor.svelte';
	import { STEP_TYPE_MIME } from './dnd';
	import { setEditorContext } from '$lib/flow/context';

	let { editor }: { editor: FlowEditor } = $props();
	// svelte-ignore state_referenced_locally
	setEditorContext(editor);

	const nodeTypes: NodeTypes = { step: StepNode };
	const edgeTypes: EdgeTypes = { flow: FlowEdge };
	const { screenToFlowPosition } = useSvelteFlow();

	const SNAP = 8;
	const snap = (n: number) => Math.round(n / SNAP) * SNAP;

	function ondragover(event: DragEvent) {
		if (!event.dataTransfer?.types.includes(STEP_TYPE_MIME)) return;
		event.preventDefault();
		event.dataTransfer.dropEffect = 'copy';
	}

	function ondrop(event: DragEvent) {
		const type = event.dataTransfer?.getData(STEP_TYPE_MIME);
		if (!type) return;
		event.preventDefault();
		const at = screenToFlowPosition({ x: event.clientX, y: event.clientY });
		editor.addStep(type, { x: snap(at.x), y: snap(at.y) });
	}

	const isValidConnection = (c: Edge | Connection) => editor.canConnect(c.source, c.target);

	// Fit only a flow that arrives with steps. On an empty canvas, a deferred fit would fire on
	// the first drop and yank the viewport away from where the operator is placing steps.
	// svelte-ignore state_referenced_locally
	const fitOnLoad = editor.nodes.length > 0;
</script>

<div class="canvas" role="application" aria-label="Flow canvas" {ondragover} {ondrop}>
	<SvelteFlow
		bind:nodes={editor.nodes}
		bind:edges={editor.edges}
		{nodeTypes}
		{edgeTypes}
		defaultEdgeOptions={{ type: 'flow' }}
		{isValidConnection}
		onconnect={() => editor.touch()}
		onconnectend={(_, state) => {
			if (state.fromNode && state.toNode && !state.isValid) {
				editor.explainRejection(state.fromNode.id, state.toNode.id);
			}
		}}
		ondelete={() => editor.touch()}
		onnodedragstop={() => editor.touch('cosmetic')}
		onmove={(_, viewport) => (editor.zoom = viewport.zoom)}
		deleteKey={['Backspace', 'Delete']}
		snapGrid={[SNAP, SNAP]}
		fitView={fitOnLoad}
		fitViewOptions={{ padding: 0.2, maxZoom: 1 }}
		proOptions={{ hideAttribution: true }}
	>
		<Background
			variant={BackgroundVariant.Dots}
			gap={16}
			size={1}
			bgColor="var(--canvas-ground)"
			patternColor="var(--color-grid-dot)"
		/>

		<Panel position="top-left">
			<div class="legend" aria-label="Edge legend">
				<span class="legend-item">
					<svg width="34" height="10" viewBox="0 0 34 10" aria-hidden="true">
						<path d="M1,5 L33,5" class="legend-sequence" />
					</svg>
					sequence
				</span>
				<span class="legend-item">
					<svg width="34" height="12" viewBox="0 0 34 12" aria-hidden="true">
						<path d="M1,2 C12,2 14,6 22,6" class="legend-join" />
						<path d="M1,10 C12,10 14,6 22,6" class="legend-join" />
						<rect x="23" y="2" width="8" height="8" transform="rotate(45 27 6)" class="legend-diamond" />
					</svg>
					join (fan-in)
				</span>
			</div>
		</Panel>

		<Controls position="bottom-left" orientation="vertical" />

		<MiniMap
			position="bottom-right"
			width={168}
			height={104}
			bgColor="var(--color-surface)"
			maskColor="color-mix(in srgb, var(--color-ground) 55%, transparent)"
			maskStrokeColor="var(--edge-sequence-color)"
			maskStrokeWidth={1}
			nodeColor={(n) => `var(--category-${(n as StepFlowNode).data.info?.category ?? 'custom'})`}
			nodeBorderRadius={0}
			ariaLabel="Minimap"
		/>
	</SvelteFlow>
</div>

<style>
	.canvas {
		position: relative;
		width: 100%;
		height: 100%;
	}

	.legend {
		display: flex;
		align-items: center;
		gap: 16px;
		padding: 7px 10px;
		background: color-mix(in srgb, var(--color-surface) 92%, transparent);
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-control);
		font-size: var(--size-micro);
		color: var(--color-text-muted);
	}

	.legend-item {
		display: inline-flex;
		align-items: center;
		gap: 7px;
	}

	.legend-sequence {
		stroke: var(--edge-sequence-color);
		stroke-width: var(--edge-sequence-width);
	}

	.legend-join {
		fill: none;
		stroke: var(--edge-join-color);
		stroke-width: var(--edge-join-width);
	}

	.legend-diamond {
		fill: var(--canvas-ground);
		stroke: var(--edge-join-color);
		stroke-width: 1.6;
	}

	.canvas :global(.svelte-flow__minimap) {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		overflow: hidden;
	}

	.canvas :global(.svelte-flow__controls) {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		overflow: hidden;
		box-shadow: none;
	}

	.canvas :global(.svelte-flow__controls-button) {
		width: 30px;
		height: 30px;
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
		color: var(--color-text);
		fill: var(--color-text);
	}

	.canvas :global(.svelte-flow__controls-button:hover) {
		background: var(--color-card-raised);
	}

	.canvas :global(.svelte-flow__controls-button svg) {
		fill: currentColor;
	}

	.canvas :global(.svelte-flow__node) {
		padding: 0;
		border: 0;
		background: transparent;
		box-shadow: none;
	}
</style>
