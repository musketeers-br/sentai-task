// Tracer-bullet fixture only — NOT `SENTAI.Model.Step`/`SENTAI.Model.Edge`.
// See specs/002-canvas-ui/data-model.md (Tracer Bullet slice).
// Exactly 3 nodes and 1 edge, compiled in. No backend call, no persistence.

export type StepCategory = 'verification' | 'storage' | 'journal' | 'purge' | 'backup' | 'custom';

export interface TracerNode {
	id: string;
	title: string;
	category: StepCategory;
}

export interface TracerEdge {
	source: string;
	target: string;
}

export const tracerNodes: TracerNode[] = [
	{ id: '01', title: 'Integrity check — USER', category: 'verification' },
	{ id: '02', title: 'Purge audit records', category: 'purge' },
	{ id: '03', title: 'Switch journal', category: 'journal' }
];

// Exactly 1 edge (data-model.md rule): renders as a sequence edge only, never a join.
export const tracerEdges: TracerEdge[] = [{ source: '01', target: '02' }];
