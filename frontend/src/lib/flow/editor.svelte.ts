import type { Edge, Node } from '@xyflow/svelte';
import { api, describeError } from '$lib/api/client';
import { checkConnection, type EdgeRef } from './graph';
import {
	createStep,
	nextStepId,
	summarize,
	toDefinition,
	type FlowDocument,
	type Position,
	type StepTypeInfo,
	type FlowStep
} from './document';
import { autoLayout } from './layout';

export type StepNodeData = { step: FlowStep; info: StepTypeInfo | undefined };
export type StepFlowNode = Node<StepNodeData, 'step'>;
export type Notice = { tone: 'error' | 'info'; text: string };

const REJECTION_TEXT = {
	self: 'A step cannot depend on itself.',
	duplicate: 'These two steps are already connected.',
	cycle: 'That edge would create a cycle — a flow must stay acyclic.'
} as const;

function toFlowEdge({ source, target }: EdgeRef): Edge {
	return { id: `${source}->${target}`, source, target, type: 'flow' };
}

export class FlowEditor {
	registry = $state.raw<StepTypeInfo[]>([]);
	nodes = $state.raw<StepFlowNode[]>([]);
	edges = $state.raw<Edge[]>([]);

	id = $state<string | null>(null);
	// Flow names are unique per instance (409 on a clash), so a fresh draft gets a dated name.
	name = $state(`Untitled flow ${new Date().toISOString().slice(0, 16).replace('T', ' ')}`);
	revision = $state(0);
	savedAt = $state<string | null>(null);
	defaultCategory = $state('Default');

	dirty = $state(false);
	saving = $state(false);
	zoom = $state(1);
	notice = $state<Notice | null>(null);

	steps = $derived(this.nodes.map((n) => n.data.step));
	edgeRefs = $derived(this.edges.map(({ source, target }) => ({ source, target })));
	summary = $derived(summarize(this.steps, this.edgeRefs, this.registry));

	info(type: string): StepTypeInfo | undefined {
		return this.registry.find((r) => r.type === type);
	}

	load(doc: FlowDocument): void {
		const positions = autoLayout(
			doc.steps.map((s) => s.id),
			doc.edges,
			doc.positions
		);
		this.id = doc.id;
		this.name = doc.name;
		this.revision = doc.revision;
		this.savedAt = doc.savedAt;
		this.defaultCategory = doc.defaultCategory;
		this.nodes = doc.steps.map((step) => this.#node(step, positions[step.id]));
		this.edges = doc.edges.map(toFlowEdge);
		this.dirty = false;
	}

	addStep(type: string, position: Position): StepFlowNode | null {
		const info = this.info(type);
		if (!info) return null;
		const step = createStep(info, nextStepId(this.steps), this.defaultCategory);
		const node = this.#node(step, position);
		this.nodes = [...this.nodes, node];
		this.touch();
		return node;
	}

	/** Fires continuously while a connection is dragged — must stay side-effect free. */
	canConnect = (source: string, target: string): boolean =>
		checkConnection(this.edgeRefs, source, target).ok;

	/** Called once when a drag ends on a step that refused the connection (FR-002). */
	explainRejection(source: string, target: string): void {
		const result = checkConnection(this.edgeRefs, source, target);
		if (!result.ok) this.notice = { tone: 'error', text: REJECTION_TEXT[result.reason] };
	}

	touch(): void {
		this.dirty = true;
	}

	toDocument(): FlowDocument {
		return {
			id: this.id,
			name: this.name,
			revision: this.revision,
			savedAt: this.savedAt,
			defaultCategory: this.defaultCategory,
			steps: this.steps,
			edges: this.edgeRefs,
			positions: Object.fromEntries(
				this.nodes.map((n) => [n.id, { x: Math.round(n.position.x), y: Math.round(n.position.y) }])
			)
		};
	}

	async save(): Promise<boolean> {
		if (this.saving) return false;
		this.saving = true;
		const definition = toDefinition(this.toDocument());
		const result = this.id
			? await api.saveFlow(this.id, this.revision, definition)
			: await api.createFlow(definition);
		this.saving = false;

		if (!result.ok) {
			this.notice = { tone: 'error', text: describeError(result.error) };
			return false;
		}
		this.id = result.value.id;
		this.revision = result.value.revision;
		this.savedAt = result.value.savedAt;
		this.dirty = false;
		this.notice = null;
		return true;
	}

	#node(step: FlowStep, position: Position): StepFlowNode {
		return { id: step.id, type: 'step', position, data: { step, info: this.info(step.type) } };
	}
}
