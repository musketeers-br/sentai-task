// Typed calls to SENTAI.REST.Dispatcher (contracts/openapi.yaml). Every predictable failure
// comes back as a value, and the platform's own words are kept verbatim (Constitution III, IV).
import type { FlowDefinition, FlowDocument, StepTypeInfo } from '$lib/flow/document';
import type { ValidationReport } from '$lib/flow/report';
import { session } from './session.svelte';
import {
	fromWireFlow,
	fromWireStepTypes,
	type WireFlow,
	type WireFlowSummary,
	type WireStepType
} from './wire';

const API_BASE = '/csp/sentai/api/v1';

export interface ScheduleResult {
	taskIds: number[];
	nextRun: string;
}

export type ApiError =
	| { kind: 'unauthorized' }
	| { kind: 'validation'; status: number; report: ValidationReport }
	| { kind: 'problem'; status: number; title: string; detail: string }
	| { kind: 'network'; message: string };

export type ApiResult<T> = { ok: true; value: T } | { ok: false; error: ApiError };

export function describeError(error: ApiError): string {
	switch (error.kind) {
		case 'unauthorized':
			return 'Your session expired. Sign in again to continue.';
		case 'validation':
			return error.report.errors.map((f) => f.message).join(' · ') || `HTTP ${error.status}`;
		case 'problem':
			return error.detail || `${error.status} ${error.title}`;
		case 'network':
			return error.message;
	}
}

async function request<T>(method: string, path: string, body?: unknown): Promise<ApiResult<T>> {
	const authorization = session.authorization();
	if (!authorization) return { ok: false, error: { kind: 'unauthorized' } };

	let res: Response;
	try {
		res = await fetch(`${API_BASE}${path}`, {
			method,
			headers: {
				Authorization: authorization,
				...(body === undefined ? {} : { 'Content-Type': 'application/json' })
			},
			body: body === undefined ? undefined : JSON.stringify(body)
		});
	} catch (e) {
		return { ok: false, error: { kind: 'network', message: (e as Error).message } };
	}

	if (res.status === 401) {
		session.expire();
		return { ok: false, error: { kind: 'unauthorized' } };
	}

	const text = await res.text();
	const json = text ? (JSON.parse(text) as Record<string, unknown>) : {};

	if (res.ok) return { ok: true, value: json as T };
	if (Array.isArray(json.errors)) {
		return { ok: false, error: { kind: 'validation', status: res.status, report: json as unknown as ValidationReport } };
	}
	return {
		ok: false,
		error: {
			kind: 'problem',
			status: res.status,
			title: String(json.title ?? res.statusText),
			detail: String(json.detail ?? '')
		}
	};
}

function map<A, B>(result: ApiResult<A>, fn: (a: A) => B): ApiResult<B> {
	return result.ok ? { ok: true, value: fn(result.value) } : result;
}

export const api = {
	async stepTypes(): Promise<ApiResult<StepTypeInfo[]>> {
		return map(await request<WireStepType[]>('GET', '/catalog/step-types'), fromWireStepTypes);
	},

	async listFlows(): Promise<ApiResult<WireFlowSummary[]>> {
		return request<WireFlowSummary[]>('GET', '/flows');
	},

	async getFlow(id: string): Promise<ApiResult<FlowDocument>> {
		return map(await request<WireFlow>('GET', `/flows/${encodeURIComponent(id)}`), fromWireFlow);
	},

	async createFlow(def: FlowDefinition): Promise<ApiResult<FlowDocument>> {
		return map(await request<WireFlow>('POST', '/flows', def), fromWireFlow);
	},

	async saveFlow(id: string, revision: number, def: FlowDefinition): Promise<ApiResult<FlowDocument>> {
		return map(
			await request<WireFlow>('PUT', `/flows/${encodeURIComponent(id)}?revision=${revision}`, def),
			fromWireFlow
		);
	},

	/** Advisory: evaluated against the live instance; dispatch re-evaluates authoritatively. */
	async validate(id: string): Promise<ApiResult<ValidationReport>> {
		return request<ValidationReport>('POST', `/flows/${encodeURIComponent(id)}/validate`, {});
	},

	async schedule(
		id: string,
		body: { scheduleSpec: string; category?: string }
	): Promise<ApiResult<ScheduleResult>> {
		return map(
			await request<{ taskIds: Array<number | string>; nextRun: string }>(
				'POST',
				`/flows/${encodeURIComponent(id)}/schedule`,
				body
			),
			(r) => ({ taskIds: r.taskIds.map(Number), nextRun: r.nextRun })
		);
	},

	async wqmCategoryNames(): Promise<ApiResult<string[]>> {
		return map(await request<Array<{ name: string }>>('GET', '/wqm/categories'), (list) =>
			list.map((c) => c.name)
		);
	}
};
