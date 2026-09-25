import { expect, type APIRequestContext, type Page } from '@playwright/test';

export const USER = process.env.IRIS_USER ?? '_SYSTEM';
export const PASSWORD = process.env.IRIS_PASSWORD ?? 'SYS';
// ServeFiles has no directory index, so the container needs the explicit file name.
const ENTRY = process.env.APP_ENTRY ?? 'index.html';
export const EVIDENCE_DIR = '../specs/002-canvas-ui/evidence';

export async function signIn(page: Page, query = ''): Promise<void> {
	await page.goto(`${ENTRY}${query}`);
	await page.getByLabel('User').fill(USER);
	await page.getByLabel('Password').fill(PASSWORD);
	await page.getByRole('button', { name: 'Sign in' }).click();
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
}

export async function token(request: APIRequestContext): Promise<string> {
	const res = await request.post('/api/admin/login', {
		headers: { Authorization: `Basic ${Buffer.from(`${USER}:${PASSWORD}`).toString('base64')}` },
		data: {}
	});
	expect(res.status()).toBe(200);
	return (await res.json()).access_token;
}

export async function seedFlow(request: APIRequestContext, definition: object): Promise<string> {
	const res = await request.post('/csp/sentai/api/v1/flows', {
		headers: { Authorization: `Bearer ${await token(request)}` },
		data: definition
	});
	expect(res.status(), await res.text()).toBe(201);
	return String((await res.json()).id);
}

/** Native %SYS.Task entries the backend created for a flow ("SentaiTask: <flowId>#<stepId>"). */
export async function nativeTaskIds(request: APIRequestContext, flowId: string): Promise<number[]> {
	const res = await request.get(`/api/admin/v2/tasks?filter=${encodeURIComponent(`SentaiTask: ${flowId}#`)}`, {
		headers: { Authorization: `Bearer ${await token(request)}` }
	});
	expect(res.status()).toBe(200);
	const rows: Array<Record<string, unknown>> = (await res.json()).result ?? [];
	return rows
		.filter((r) => String(r.Name ?? r.name ?? '').startsWith(`SentaiTask: ${flowId}#`))
		.map((r) => Number(r.ID ?? r.Id ?? r.id));
}

export async function deleteNativeTask(request: APIRequestContext, taskId: number): Promise<void> {
	const res = await request.delete(`/api/admin/v2/task?id=${taskId}`, {
		headers: { Authorization: `Bearer ${await token(request)}` }
	});
	expect(res.ok(), `DELETE task ${taskId}: ${res.status()} ${await res.text()}`).toBe(true);
}

/** Spec 001's evidence envelope, trimmed to what a UI-driven capture can observe. */
export function envelope(evidenceId: string, request: object, response: object, notes: string[] = []) {
	return JSON.stringify(
		{ evidence_id: evidenceId, captured_at: new Date().toISOString(), request, response, notes },
		null,
		2
	);
}

/** Drags from one step's output handle to another step's input handle. */
export async function connect(page: Page, from: string, to: string): Promise<void> {
	const source = page.locator(`.svelte-flow__node[data-id="${from}"] .svelte-flow__handle.source`);
	const target = page.locator(`.svelte-flow__node[data-id="${to}"] .svelte-flow__handle.target`);
	const a = (await source.boundingBox())!;
	const b = (await target.boundingBox())!;
	await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
	await page.mouse.down();
	await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 12 });
	await page.mouse.up();
}

export const edge = (page: Page, from: string, to: string) =>
	page.locator(`.svelte-flow__edge[aria-label="Edge from ${from} to ${to}"]`);

/** "#RRGGBB" → "rgb(r, g, b)", the form getComputedStyle reports colours in. */
export function hexToRgb(hex: string): string {
	const n = Number.parseInt(hex.trim().slice(1), 16);
	return `rgb(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255})`;
}

interface SeedStep {
	id: string;
	type: string;
	taskName: string;
	namespace: string;
	runAsUser: string;
	wqmCategory: string;
	databaseDirectory?: string;
	timeoutMinutes?: number;
	parameters?: Record<string, unknown>;
}

/**
 * The canonical UI-001 shape (3-into-1 fan-in, then a sequence step) built only from
 * `integrity-check`, the one type spec 004 proved runnable in v1 — so it validates clean.
 */
export function v1Flow(name: string) {
	const flow = canonicalFlow(name);
	const ic = (id: string, taskName: string, namespace: string, databaseDirectory: string): SeedStep => ({
		id,
		type: 'integrity-check',
		taskName,
		namespace,
		runAsUser: 'irisadm',
		wqmCategory: 'Default',
		databaseDirectory,
		timeoutMinutes: 30
	});
	return {
		...flow,
		steps: [
			flow.steps[0],
			flow.steps[1],
			flow.steps[2],
			ic('04', 'Integrity check — IRISAPP (after the wave)', 'IRISAPP', '/data/IRISAPP_DATA/'),
			ic('05', 'Integrity check — USER (final)', 'USER', '/usr/irissys/mgr/user/')
		]
	};
}

/** The canonical UI-001 graph, on namespaces that exist in the dev image. */
export function canonicalFlow(name: string) {
	const step = (id: string, type: string, taskName: string, extra: Partial<SeedStep> = {}): SeedStep => ({
		id,
		type,
		taskName,
		namespace: '%SYS',
		runAsUser: 'irisadm',
		wqmCategory: 'Default',
		...extra
	});
	return {
		name,
		defaultCategory: 'Default',
		steps: [
			step('01', 'integrity-check', 'Integrity check — USER', {
				namespace: 'USER',
				databaseDirectory: '/usr/irissys/mgr/user/',
				timeoutMinutes: 90
			}),
			step('02', 'integrity-check', 'Integrity check — IRISAPP', {
				namespace: 'IRISAPP',
				databaseDirectory: '/data/IRISAPP_DATA/',
				timeoutMinutes: 45
			}),
			step('03', 'integrity-check', 'Integrity check — IRISSYS', {
				databaseDirectory: '/usr/irissys/mgr/',
				timeoutMinutes: 45
			}),
			step('04', 'purge-audit-records', 'Purge audit records', {
				timeoutMinutes: 20,
				parameters: { daysToKeep: 30 }
			}),
			step('05', 'switch-journal', 'Switch journal', { timeoutMinutes: 5 })
		],
		edges: [
			{ source: '01', target: '04' },
			{ source: '02', target: '04' },
			{ source: '03', target: '04' },
			{ source: '04', target: '05' }
		],
		joins: [{ target: '04', policy: 'ALL_MUST_SUCCEED' }],
		canvasGeometry: {
			nodes: {
				'01': { x: 40, y: 40 },
				'02': { x: 40, y: 232 },
				'03': { x: 40, y: 424 },
				'04': { x: 400, y: 216 },
				'05': { x: 720, y: 248 }
			}
		}
	};
}
