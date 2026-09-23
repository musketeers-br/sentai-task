import type { EdgeRef } from './graph';
import type { Position } from './document';

const COLUMN = 320;
const ROW = 180;

/** Column = longest path from a root; row = order within the column. Existing positions win. */
export function autoLayout(
	stepIds: string[],
	edges: EdgeRef[],
	existing: Record<string, Position> = {}
): Record<string, Position> {
	const depth = new Map<string, number>(stepIds.map((id) => [id, 0]));
	// Relax edges repeatedly; bounded by the node count because the graph is acyclic.
	for (let i = 0; i < stepIds.length; i++) {
		for (const e of edges) {
			const next = (depth.get(e.source) ?? 0) + 1;
			if (next > (depth.get(e.target) ?? 0)) depth.set(e.target, next);
		}
	}

	const rowInColumn = new Map<number, number>();
	const positions: Record<string, Position> = {};
	for (const id of [...stepIds].sort()) {
		if (existing[id]) {
			positions[id] = existing[id];
			continue;
		}
		const column = depth.get(id) ?? 0;
		const row = rowInColumn.get(column) ?? 0;
		rowInColumn.set(column, row + 1);
		positions[id] = { x: column * COLUMN, y: row * ROW };
	}
	return positions;
}
