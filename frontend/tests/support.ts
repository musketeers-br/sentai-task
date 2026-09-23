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

async function token(request: APIRequestContext): Promise<string> {
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

/** The canonical UI-001 graph, on namespaces that exist in the dev image. */
export function canonicalFlow(name: string) {
	const step = (id: string, type: string, taskName: string, extra: object = {}) => ({
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
