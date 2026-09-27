import { targetsUsedBy, type TargetView } from '$lib/targets/targets';
import { refusalText } from '$lib/catalog/catalog';
import type { Edge, Node } from '@xyflow/svelte';
import { api, describeError, type ApiResult, type ScheduleResult } from '$lib/api/client';
import { defaultFlowName } from '$lib/flows/list';
import { session } from '$lib/api/session.svelte';
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
import { findingsForStep, type StepFindings, type ValidationReport } from './report';

export type StepNodeData = { step: FlowStep; info: StepTypeInfo | undefined };
export type StepFlowNode = Node<StepNodeData, 'step'>;
export type Notice = { tone: 'error' | 'info'; text: string };

/**
 * `graph` edits change what the flow does (steps, edges, step settings) and make the last
 * validation report obsolete; `cosmetic` edits (moving a node, renaming the flow) do not.
 */
export type ChangeKind = 'graph' | 'cosmetic';

export type ScheduleOutcome =
	| { ok: true; result: ScheduleResult }
	| { ok: false; message: string; report: ValidationReport | null };

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
	wqmCategories = $state.raw<string[]>([]);
	/** Spec 009: registered target servers, as GET /targets returns them (for *Run on*). */
	targets = $state.raw<TargetView[]>([]);
	nodes = $state.raw<StepFlowNode[]>([]);
	edges = $state.raw<Edge[]>([]);

	id = $state<string | null>(null);
	// Flow names are unique per instance (409 on a clash), so a fresh draft gets a dated name.
	name = $state(defaultFlowName(new Date(), []));
	/** The name the platform last confirmed; null for a draft never saved (spec 010 FR-005). */
	savedName = $state<string | null>(null);
	revision = $state(0);
	savedAt = $state<string | null>(null);
	defaultCategory = $state('Default');

	dirty = $state(false);
	saving = $state(false);
	validating = $state(false);
	zoom = $state(1);
	notice = $state<Notice | null>(null);
	/** A 409 on *Save flow*: the status bar adds "Use Save as… to keep your version." (spec 010). */
	conflictHint = $state(false);
	/** Last report from POST /validate; cleared by any `graph` change. */
	report = $state.raw<ValidationReport | null>(null);

	steps = $derived(this.nodes.map((n) => n.data.step));
	edgeRefs = $derived(this.edges.map(({ source, target }) => ({ source, target })));
	summary = $derived(summarize(this.steps, this.edgeRefs, this.registry));
	selectedNode = $derived.by(() => {
		const selected = this.nodes.filter((n) => n.selected);
		return selected.length === 1 ? selected[0] : null;
	});
	/** Spec 010 FR-005: saving now would rename the open flow rather than create a copy. */
	renaming = $derived(this.id !== null && this.savedName !== null && this.name.trim() !== this.savedName);
	/** FR-010: only errors block scheduling — and only errors we actually know about. */
	scheduleBlocked = $derived((this.report?.errors.length ?? 0) > 0);

	info(type: string): StepTypeInfo | undefined {
		return this.registry.find((r) => r.type === type);
	}

	findingsFor(stepId: string): StepFindings {
		return findingsForStep(this.report, stepId);
	}

	load(doc: FlowDocument): void {
		const positions = autoLayout(
			doc.steps.map((s) => s.id),
			doc.edges,
			doc.positions
		);
		this.id = doc.id;
		this.name = doc.name;
		this.savedName = doc.id === null ? null : doc.name;
		this.conflictHint = false;
		this.revision = doc.revision;
		this.savedAt = doc.savedAt;
		this.defaultCategory = doc.defaultCategory;
		this.nodes = doc.steps.map((step) => this.#node(step, positions[step.id]));
		this.edges = doc.edges.map(toFlowEdge);
		this.report = null;
		this.dirty = false;
	}

	addStep(type: string, position: Position): StepFlowNode | null {
		const info = this.info(type);
		if (!info) return null;
		if (!info.available) {
			this.notice = { tone: 'error', text: `${info.type} is not supported on the target platform in v1.` };
			return null;
		}
		const step = createStep(info, nextStepId(this.steps), this.defaultCategory);
		const node = this.#node(step, position);
		this.nodes = [...this.nodes, node];
		this.touch('graph');
		return node;
	}

	updateStep(id: string, patch: Partial<Omit<FlowStep, 'id' | 'type'>>): void {
		this.nodes = this.nodes.map((n) =>
			n.id === id ? { ...n, data: { ...n.data, step: { ...n.data.step, ...patch } } } : n
		);
		this.touch('graph');
	}

	/** Fires continuously while a connection is dragged — must stay side-effect free. */
	canConnect = (source: string, target: string): boolean =>
		checkConnection(this.edgeRefs, source, target).ok;

	/** Called once when a drag ends on a step that refused the connection (FR-002). */
	explainRejection(source: string, target: string): void {
		const result = checkConnection(this.edgeRefs, source, target);
		if (!result.ok) this.notice = { tone: 'error', text: REJECTION_TEXT[result.reason] };
	}

	touch(kind: ChangeKind = 'graph'): void {
		this.dirty = true;
		if (kind === 'graph') this.report = null;
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
			this.conflictHint = result.error.kind === 'problem' && result.error.status === 409 && this.id !== null;
			return false;
		}
		this.id = result.value.id;
		this.revision = result.value.revision;
		this.savedAt = result.value.savedAt;
		this.savedName = result.value.name;
		this.dirty = false;
		this.notice = null;
		this.conflictHint = false;
		return true;
	}

	/**
	 * Spec 010 FR-004: a **new** flow from this canvas — unsaved edits included — under `name`.
	 * The open flow is never PUT, so it keeps its last saved revision. On success the editor holds
	 * the new flow; on a refusal nothing changes and the platform's error is returned to the dialog.
	 */
	async saveAs(name: string): Promise<ApiResult<FlowDocument>> {
		const definition = toDefinition({ ...this.toDocument(), id: null, name });
		this.saving = true;
		const result = await api.createFlow(definition);
		this.saving = false;
		if (result.ok) {
			this.load(result.value);
			this.notice = null;
		}
		return result;
	}

	/** Spec 010 FR-007: an empty draft with a fresh name; the caller drops the flow from the address. */
	reset(name: string): void {
		this.nodes = [];
		this.edges = [];
		this.id = null;
		this.name = name;
		this.savedName = null;
		this.revision = 0;
		this.savedAt = null;
		this.report = null;
		this.notice = null;
		this.conflictHint = false;
		this.dirty = false;
	}

	/** Validation reads the persisted flow, so unsaved edits are saved first (FR-019). */
	async validate(): Promise<ValidationReport | null> {
		if (this.validating) return null;
		if ((this.dirty || !this.id) && !(await this.save())) return null;
		this.validating = true;
		const result = await api.validate(this.id!);
		this.validating = false;
		if (!result.ok) {
			this.notice = { tone: 'error', text: describeError(result.error) };
			return null;
		}
		this.report = result.value;
		this.notice =
			result.value.errors.length + result.value.warnings.length === 0
				? { tone: 'info', text: 'Flow is valid — no errors, no warnings.' }
				: null;
		return result.value;
	}

	/**
	 * Dispatch validates authoritatively server-side (FR-018); its 422 lands on the canvas.
	 * The run is given its own login (session.dedicatedToken) so this session's token refreshes
	 * cannot revoke the credential the run depends on.
	 */
	async dispatch(
		password: string,
		confirmations: Array<{ stepId: string; typedName: string }> = [],
		targetPasswords: Record<string, string> = {}
	): Promise<{ ok: true; guid: string } | { ok: false; message: string }> {
		if ((this.dirty || !this.id) && !(await this.save())) {
			return { ok: false, message: this.notice?.text ?? 'Save failed.' };
		}
		const credential = await session.dedicatedToken(password);
		if (!credential.ok) return credential;
		// Spec 009 FR-009: one sign-in per target the flow uses; any refusal stops here, verbatim.
		const targetCredentials: Array<{ target: string; refreshToken: string }> = [];
		for (const target of targetsUsedBy(this.steps)) {
			const signedIn = await api.signInTarget(target, targetPasswords[target] ?? '');
			if (!signedIn.ok) return { ok: false, message: `Target ${target}: ${refusalText(signedIn.error)}` };
			targetCredentials.push({ target, refreshToken: signedIn.value.refreshToken });
		}
		const result = await api.dispatch(this.id!, credential, confirmations, targetCredentials);
		if (result.ok) return { ok: true, guid: result.value.guid };
		if (result.error.kind === 'validation') this.report = result.error.report;
		return { ok: false, message: `Not dispatched: ${describeError(result.error)}` };
	}

	async schedule(scheduleSpec: string, category: string): Promise<ScheduleOutcome> {
		if ((this.dirty || !this.id) && !(await this.save())) {
			return { ok: false, message: this.notice?.text ?? 'Save failed.', report: null };
		}
		const result = await api.schedule(this.id!, {
			scheduleSpec,
			...(category ? { category } : {})
		});
		if (result.ok) return { ok: true, result: result.value };
		// A 422 is the same ValidationReport shape: show it on the canvas as well.
		if (result.error.kind === 'validation') this.report = result.error.report;
		return {
			ok: false,
			message: describeError(result.error),
			report: result.error.kind === 'validation' ? result.error.report : null
		};
	}

	#node(step: FlowStep, position: Position): StepFlowNode {
		return { id: step.id, type: 'step', position, data: { step, info: this.info(step.type) } };
	}
}
