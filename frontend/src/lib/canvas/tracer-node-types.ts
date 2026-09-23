import type { Node } from '@xyflow/svelte';
import type { StepCategory } from '$lib/fixtures/tracer-graph';

export type TracerFlowNode = Node<
	{ stepId: string; title: string; category: StepCategory },
	'tracer'
>;
