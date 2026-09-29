/// <reference types="node" />
// Spec 012 e2e helpers: dispatching quick, read-only flows through the API and waiting for them.
import { expect, type APIRequestContext } from '@playwright/test';
import { PASSWORD, seedFlow, USER } from './support';

const API = '/csp/sentai/api/v1';

async function pair(request: APIRequestContext): Promise<{ access: string; refresh: string }> {
	const res = await request.post('/api/admin/login', {
		headers: { Authorization: `Basic ${Buffer.from(`${USER}:${PASSWORD}`).toString('base64')}` },
		data: {}
	});
	expect(res.status()).toBe(200);
	const body = await res.json();
	return { access: body.access_token, refresh: body.refresh_token };
}

/** Two in-process, read-only steps: the run ends in about a second. */
export function quickFlow(name: string) {
	const step = (id: string, type: string, taskName: string, parameters: object) => ({
		id,
		type,
		taskName,
		namespace: '%SYS',
		wqmCategory: 'Default',
		timeoutMinutes: 10,
		parameters
	});
	return {
		name,
		defaultCategory: 'Default',
		steps: [step('01', 'storage-headroom-check', 'Storage headroom', { minFreePercent: 0 }), step('02', 'db-size-report', 'Database sizes', {})],
		edges: [],
		joins: []
	};
}

/** 01 always fails (100 % free is impossible), 02 waits for it behind an all-must-succeed join. */
export function failingFlow(name: string) {
	const flow = quickFlow(name);
	flow.steps[0].parameters = { minFreePercent: 100 };
	return { ...flow, edges: [{ source: '01', target: '02' }], joins: [{ target: '02', policy: 'ALL_MUST_SUCCEED' }] };
}

export async function seedQuickFlow(request: APIRequestContext, name: string, definition: object = quickFlow(name)): Promise<string> {
	return seedFlow(request, definition);
}

/** Dispatches `flowId` with a run credential and waits until the run is no longer running. */
export async function runToEnd(request: APIRequestContext, flowId: string): Promise<{ guid: string; state: string }> {
	const run = await pair(request);
	const res = await request.post(`${API}/flows/${flowId}/dispatch`, {
		headers: { Authorization: `Bearer ${run.access}` },
		data: { confirmations: [], runCredential: { refreshToken: run.refresh } }
	});
	expect(res.status(), await res.text()).toBe(202);
	const guid = String((await res.json()).guid);
	let state = 'running';
	for (let i = 0; i < 60 && state === 'running'; i++) {
		await new Promise((r) => setTimeout(r, 1000));
		const { access } = await pair(request);
		const read = await request.get(`${API}/runs/${guid}`, { headers: { Authorization: `Bearer ${access}` } });
		state = (await read.json()).state;
	}
	return { guid, state };
}

export async function readRun(request: APIRequestContext, guid: string): Promise<Record<string, unknown>> {
	const { access } = await pair(request);
	const read = await request.get(`${API}/runs/${guid}`, { headers: { Authorization: `Bearer ${access}` } });
	expect(read.status()).toBe(200);
	return read.json();
}
