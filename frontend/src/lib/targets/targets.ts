// Target servers as the spec 008 API reports them (spec 009). This module and src/lib/api/client.ts
// are the only ones that know the wire shapes; components receive only these types. Nothing here
// decides whether a target is usable: reachability, capability and permission are the API's.
import type { PlatformStatus } from '$lib/api/client';
import { refusalText } from '$lib/catalog/catalog';
import type { FlowStep, StepTypeInfo } from '$lib/flow/document';

export interface WireTarget {
	name: string;
	baseUrl: string;
	description?: string;
	online: boolean;
	createdAt?: string;
	updatedAt?: string;
}

export interface WireTargetStatus {
	target: string;
	readAt: string;
	reachable: boolean;
	version?: string;
	user?: string;
	categories?: Array<Record<string, unknown>>;
	unreachable?: { transportError: string };
	refused?: { status: number; title?: string; detail?: string; httpStatus?: number; platformStatus?: PlatformStatus };
}

export interface TargetView {
	name: string;
	baseUrl: string;
	description: string;
	online: boolean;
}

/** What the target reported, or why it could not: every value verbatim, nothing computed. */
export type TargetStatusView =
	| { kind: 'reachable'; readAt: string; version: string; user: string; categories: Array<Record<string, unknown>> }
	| { kind: 'unreachable'; readAt: string; transportError: string }
	| { kind: 'refused'; readAt: string; text: string };

export function fromWireTarget(w: WireTarget): TargetView {
	return { name: w.name, baseUrl: w.baseUrl, description: w.description ?? '', online: w.online === true };
}

export function fromWireTargetStatus(w: WireTargetStatus): TargetStatusView {
	if (w.unreachable) return { kind: 'unreachable', readAt: w.readAt, transportError: w.unreachable.transportError };
	if (w.refused) {
		const r = w.refused;
		return {
			kind: 'refused',
			readAt: w.readAt,
			text: refusalText({ kind: 'problem', status: r.httpStatus ?? r.status, title: r.title ?? '', detail: r.detail ?? '', platformStatus: r.platformStatus })
		};
	}
	return { kind: 'reachable', readAt: w.readAt, version: w.version ?? '', user: w.user ?? '', categories: w.categories ?? [] };
}

/** The targets a flow's steps name, once each, in step-id order: one password each at Run now. */
export function targetsUsedBy(steps: Array<Pick<FlowStep, 'id' | 'target'>>): string[] {
	const ordered = [...steps].sort((a, b) => a.id.localeCompare(b.id));
	return [...new Set(ordered.map((s) => s.target).filter((t): t is string => !!t))];
}

/**
 * *Run on* choices (spec 009 FR-006): the online targets, for a type the API marks remote-capable;
 * none otherwise. A convenience only — the API validates every placement.
 */
export function targetChoices(targets: TargetView[], info: StepTypeInfo | undefined): TargetView[] {
	if (!info?.remoteCapable) return [];
	return targets.filter((t) => t.online);
}
