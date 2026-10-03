// Spec 022 US1 (data-model §3): the pure geometry behind a runbook card's mini-graph. The
// definition's `canvasGeometry` (authored data, never a layout algorithm) is scaled into the
// card's viewBox, edges are anchored on the borders they cross, labels come from the registry.
// No DOM, no Svelte — MiniGraph.svelte only renders what this computes.
import type { FlowDefinition, StepTypeInfo } from '$lib/flow/document';
import { typeLabel } from '$lib/flow/document';
/** The card's drawing area (SVG units); MiniGraph.svelte uses the same constants. */
export const VIEW = { width: 260, height: 104, padding: 8 };

/** Every node is one uniform box (a minimap, not a replica); labels clip inside it. */
const NODE = { width: 46, height: 18 };
/** The canvas box a geometry row describes when it carries no explicit width. */
const SOURCE_NODE = { width: 240, height: 64 };

export interface MiniNode {
	id: string;
	x: number;
	y: number;
	width: number;
	height: number;
	label: string;
	destructive: boolean;
}

export interface MiniEdge {
	/** The point on the source node's border the line leaves from. */
	from: { x: number; y: number };
	/** The point on the target node's border the line arrives at. */
	to: { x: number; y: number };
}

export interface MiniGraph {
	nodes: MiniNode[];
	edges: MiniEdge[];
	viewBox: { width: number; height: number };
}

interface Box {
	x: number;
	y: number;
	width: number;
	height: number;
}

const centre = (b: Box) => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 });

/**
 * The border pair an edge crosses, from the two boxes' relative position: left-to-right when the
 * target sits to the right (and the mirror), bottom-to-top when they share a column and the
 * target is below (and the mirror).
 */
function anchors(from: Box, to: Box): MiniEdge {
	const a = centre(from);
	const b = centre(to);
	if (to.x >= from.x + from.width) return { from: { x: from.x + from.width, y: a.y }, to: { x: to.x, y: b.y } };
	if (to.x + to.width <= from.x) return { from: { x: from.x, y: a.y }, to: { x: to.x + to.width, y: b.y } };
	if (to.y >= from.y + from.height) return { from: { x: a.x, y: from.y + from.height }, to: { x: b.x, y: to.y } };
	return { from: { x: a.x, y: from.y }, to: { x: b.x, y: to.y + to.height } };
}

/** Scales the definition's authored geometry into the card's viewBox, preserving the layout. */
export function miniGraph(definition: FlowDefinition, registry: readonly StepTypeInfo[]): MiniGraph {
	const rows = definition.steps.map((step) => {
		const geometry = definition.canvasGeometry.nodes[step.id] ?? { x: 0, y: 0 };
		return {
			id: step.id,
			type: step.type,
			x: geometry.x,
			y: geometry.y,
			width: geometry.width ?? SOURCE_NODE.width,
			height: SOURCE_NODE.height
		};
	});

	const minX = rows.reduce((m, r) => Math.min(m, r.x), Infinity);
	const minY = rows.reduce((m, r) => Math.min(m, r.y), Infinity);
	const maxX = rows.reduce((m, r) => Math.max(m, r.x + r.width), -Infinity);
	const maxY = rows.reduce((m, r) => Math.max(m, r.y + r.height), -Infinity);
	const room = { width: VIEW.width - 2 * VIEW.padding, height: VIEW.height - 2 * VIEW.padding };
	const scale = Math.min(room.width / (maxX - minX || 1), room.height / (maxY - minY || 1));

	const boxes = new Map<string, Box>();
	const nodes: MiniNode[] = rows.map((row) => {
		const info = registry.find((r) => r.type === row.type);
		const box: Box = {
			x: VIEW.padding + (row.x - minX) * scale + ((row.width * scale - NODE.width) / 2),
			y: VIEW.padding + (row.y - minY) * scale + ((row.height * scale - NODE.height) / 2),
			width: NODE.width,
			height: NODE.height
		};
		boxes.set(row.id, box);
		return {
			id: row.id,
			...box,
			label: info ? typeLabel(info) : row.id,
			destructive: info?.destructive ?? false
		};
	});

	const edges: MiniEdge[] = definition.edges.map((edge) => {
		const from = boxes.get(edge.source);
		const to = boxes.get(edge.target);
		if (!from || !to) return { from: { x: VIEW.padding, y: VIEW.padding }, to: { x: VIEW.padding, y: VIEW.padding } };
		return anchors(from, to);
	});

	return { nodes, edges, viewBox: { width: VIEW.width, height: VIEW.height } };
}
