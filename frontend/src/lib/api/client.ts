// Typed calls to SENTAI.REST.Dispatcher (contracts/openapi.yaml). Every predictable failure
// comes back as a value, and the platform's own words are kept verbatim (Constitution III, IV).
import { fromWireRunSummary, pageParams, type RunSummaryView, type RunsQuery } from '$lib/runs/runs';
import {
	catalogQuery,
	fromWireCatalogPage,
	NO_FILTERS,
	fromWireCatalogTask,
	type CatalogFilters,
	type CatalogPage,
	type CatalogTaskView,
	type WireCatalogPage,
	type WireCatalogTask
} from '$lib/catalog/catalog';
import type { FlowDefinition, FlowDocument, StepTypeInfo } from '$lib/flow/document';
import {
	fromWireTarget,
	fromWireTargetStatus,
	type TargetStatusView,
	type TargetView,
	type WireTarget,
	type WireTargetStatus
} from '$lib/targets/targets';
import type { ValidationReport } from '$lib/flow/report';
import { fromWireRun, type RunView } from '$lib/run/run';
import { session } from './session.svelte';
import { fromWireScheduleRead, type ScheduleRead, type ScheduleRequest } from '$lib/shell/schedule';
import type { FlowSummaryView } from '$lib/flows/list';
import {
	fromWireFlow,
	fromWireFlowSummary,
	fromWireStepTypes,
	type WireFlow,
	type WireFlowSummary,
	type WireStepType
} from './wire';

const API_BASE = '/csp/sentai/api/v1';

/** Spec 015: POST /flows/{id}/schedule. `residue` lists old items the platform would not remove. */
export interface ScheduleResult {
	taskId: number;
	nextRun: string | null;
	describe: string;
	residue: Array<{ task?: number; secret?: string; detail: string }>;
}

/** The platform's own error object, as spec 006 passes it through (never rewritten). */
export interface PlatformStatus {
	errors: Array<{ error: string }>;
	summary: string;
}

export type ApiError =
	| { kind: 'unauthorized' }
	| { kind: 'validation'; status: number; report: ValidationReport }
	| {
			kind: 'problem';
			status: number;
			title: string;
			detail: string;
			platformStatus?: PlatformStatus;
			platformInfo?: Record<string, unknown>;
			/** Spec 015: a machine-readable code, the field or the instance a refusal is about. */
			code?: string;
			field?: string;
			instance?: string;
	  }
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

async function request<T>(
	method: string,
	path: string,
	body?: unknown,
	authorizationOverride?: string,
	extraHeaders: Record<string, string> = {}
): Promise<ApiResult<T>> {
	const authorization = authorizationOverride ?? session.authorization();
	if (!authorization) return { ok: false, error: { kind: 'unauthorized' } };

	let res: Response;
	try {
		res = await fetch(`${API_BASE}${path}`, {
			method,
			headers: {
				Authorization: authorization,
				...extraHeaders,
				...(body === undefined ? {} : { 'Content-Type': 'application/json' })
			},
			body: body === undefined ? undefined : JSON.stringify(body)
		});
	} catch (e) {
		return { ok: false, error: { kind: 'network', message: (e as Error).message } };
	}

	const text = await res.text();
	let json: Record<string, unknown> = {};
	try {
		json = text ? (JSON.parse(text) as Record<string, unknown>) : {};
	} catch {
		json = {};
	}

	// A 401 is this session's expiry — unless the body says it is a target server's answer, which
	// spec 008 passes through with the target's own `httpStatus` (a wrong target password must never
	// sign the operator out of the canvas; spec 009 us15 finding).
	if (res.status === 401 && json.httpStatus === undefined) {
		session.expire();
		return { ok: false, error: { kind: 'unauthorized' } };
	}

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
			detail: String(json.detail ?? ''),
			...(json.platformStatus === undefined ? {} : { platformStatus: json.platformStatus as PlatformStatus }),
			...(json.platformInfo === undefined ? {} : { platformInfo: json.platformInfo as Record<string, unknown> }),
			...(typeof json.code === 'string' ? { code: json.code } : {}),
			...(typeof json.field === 'string' ? { field: json.field } : {}),
			...(typeof json.instance === 'string' ? { instance: json.instance } : {})
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

	/** Spec 010 FR-002: every flow the platform returns for the operator; never cached. */
	async listFlows(): Promise<ApiResult<FlowSummaryView[]>> {
		return map(await request<WireFlowSummary[]>('GET', '/flows'), (list) => list.map(fromWireFlowSummary));
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

	/** Spec 015: the body carries the run-as passwords; it is sent once and never kept. */
	async schedule(id: string, body: ScheduleRequest): Promise<ApiResult<ScheduleResult>> {
		return map(
			await request<Record<string, unknown>>('POST', `/flows/${encodeURIComponent(id)}/schedule`, body),
			(r) => ({
				taskId: Number(r.taskId),
				nextRun: r.nextRun ? String(r.nextRun) : null,
				describe: String(r.describe ?? ''),
				residue: Array.isArray(r.residue) ? (r.residue as ScheduleResult['residue']) : []
			})
		);
	},

	async getSchedule(id: string): Promise<ApiResult<ScheduleRead>> {
		return map(await request<Record<string, unknown>>('GET', `/flows/${encodeURIComponent(id)}/schedule`), fromWireScheduleRead);
	},

	async unschedule(id: string): Promise<ApiResult<{ removedTasks: number[]; removedSecrets: number; residue: ScheduleResult['residue'] }>> {
		return request('DELETE', `/flows/${encodeURIComponent(id)}/schedule`);
	},

	/**
	 * 202 → the run GUID; 422 → ValidationReport; 428 → Problem naming the step (FR-013), shown
	 * verbatim. `confirmations` carries one typed value per destructive step (spec 007 D-7).
	 * The run's dedicated sign-in (session.dedicatedToken): its access token authorizes the call,
	 * its refresh token (`runCredential`, E-1) lets the backend keep the run's credential alive.
	 */
	async dispatch(
		flowId: string,
		run: { authorization: string; refreshToken: string },
		confirmations: Array<{ stepId: string; typedName: string }> = [],
		targetCredentials: Array<{ target: string; refreshToken: string }> = []
	): Promise<ApiResult<{ guid: string }>> {
		return map(
			await request<{ guid: string }>(
				'POST',
				`/flows/${encodeURIComponent(flowId)}/dispatch`,
				{
					confirmations,
					runCredential: { refreshToken: run.refreshToken },
					// Spec 008 FR-010: only a flow that uses targets sends them (spec 009 FR-010).
					...(targetCredentials.length > 0 ? { targetCredentials } : {})
				},
				run.authorization
			),
			(r) => ({ guid: String(r.guid) })
		);
	},

	/** Spec 012 US2: one page of runs, newest first; `before` is the last seq already shown. */
	async listRuns(query: RunsQuery, before: number | null): Promise<ApiResult<RunSummaryView[]>> {
		return map(await request<Record<string, unknown>[]>('GET', `/runs?${pageParams(query, before)}`), (list) =>
			list.map(fromWireRunSummary)
		);
	},

	async getRun(guid: string): Promise<ApiResult<RunView>> {
		return map(await request<Record<string, unknown>>('GET', `/runs/${encodeURIComponent(guid)}`), fromWireRun);
	},

	async runAction(guid: string, action: 'cancel' | 'pause'): Promise<ApiResult<unknown>> {
		return request('POST', `/runs/${encodeURIComponent(guid)}/${action}`, {});
	},

	async stepAction(runGuid: string, stepGuid: string, action: 'cancel' | 'rerun'): Promise<ApiResult<unknown>> {
		return request(
			'POST',
			`/runs/${encodeURIComponent(runGuid)}/steps/${encodeURIComponent(stepGuid)}/${action}`,
			{}
		);
	},

	/** Spec 006: the platform's Task Manager tasks, every value as the platform reported it. */
	async catalogTasks(filters: CatalogFilters = NO_FILTERS): Promise<ApiResult<CatalogPage>> {
		return map(await request<WireCatalogPage>('GET', `/catalog/tasks${catalogQuery(filters)}`), fromWireCatalogPage);
	},

	/** One task's item read (spec 006): the list's fields plus `recentRuns`. */
	async catalogTask(taskId: number): Promise<ApiResult<CatalogTaskView>> {
		return map(await request<WireCatalogTask>('GET', `/catalog/tasks/${taskId}`), fromWireCatalogTask);
	},

	/** Spec 006: suspend or resume; a 200 carries the task as re-read after the call. */
	async setSuspended(taskId: number, suspended: boolean): Promise<ApiResult<CatalogTaskView>> {
		return map(
			await request<WireCatalogTask>('POST', `/catalog/tasks/${taskId}/suspend`, { suspended }),
			fromWireCatalogTask
		);
	},

	// --- Target servers (spec 008 API, spec 009 screens) ---

	async listTargets(): Promise<ApiResult<TargetView[]>> {
		return map(await request<WireTarget[]>('GET', '/targets'), (list) => list.map(fromWireTarget));
	},

	async createTarget(body: { name: string; baseUrl: string; description: string }): Promise<ApiResult<TargetView>> {
		return map(await request<WireTarget>('POST', '/targets', body), fromWireTarget);
	},

	async updateTarget(name: string, body: { baseUrl: string; description: string }): Promise<ApiResult<TargetView>> {
		return map(await request<WireTarget>('PUT', `/targets/${encodeURIComponent(name)}`, body), fromWireTarget);
	},

	async deleteTarget(name: string): Promise<ApiResult<unknown>> {
		return request('DELETE', `/targets/${encodeURIComponent(name)}`);
	},

	async setTargetOnline(name: string, online: boolean): Promise<ApiResult<TargetView>> {
		return map(await request<WireTarget>('POST', `/targets/${encodeURIComponent(name)}/online`, { online }), fromWireTarget);
	},

	/**
	 * Spec 008 FR-022: signs the operator in to a target through the primary, as the signed-in user.
	 * The password goes in this one request and is not kept; the pair is the caller's to drop.
	 */
	async signInTarget(name: string, password: string): Promise<ApiResult<{ accessToken: string; refreshToken: string; sub: string }>> {
		return map(
			await request<{ accessToken: string; refreshToken: string; sub: string }>(
				'POST',
				`/targets/${encodeURIComponent(name)}/sign-in`,
				{ user: session.user ?? '', password }
			),
			(r) => ({ accessToken: r.accessToken, refreshToken: r.refreshToken, sub: r.sub })
		);
	},

	/** What the target reports now, read with the operator's credential for it. */
	async targetStatus(name: string, accessToken: string): Promise<ApiResult<TargetStatusView>> {
		return map(
			await request<WireTargetStatus>('GET', `/targets/${encodeURIComponent(name)}/status`, undefined, undefined, {
				'X-Sentai-Target-Authorization': `Bearer ${accessToken}`
			}),
			fromWireTargetStatus
		);
	},

	async wqmCategoryNames(): Promise<ApiResult<string[]>> {
		return map(await request<Array<{ name: string }>>('GET', '/wqm/categories'), (list) =>
			list.map((c) => c.name)
		);
	}
};
