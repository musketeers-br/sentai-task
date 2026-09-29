/// <reference types="node" />
// Spec 014 US1: records the showcase flow running, and the stills. Run through
// scripts/media/make-media.sh, which converts the video and checks sizes. Fails — and so writes no
// media — when the target server is missing or the run does not complete (FR-004).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import { CAPTION_INIT, CAPTIONS, type Scene } from './captions';

const USER = process.env.IRIS_USER ?? '_SYSTEM';
const PASSWORD = process.env.SENTAI_MEDIA_PASSWORD ?? 'SYS';
const API = '/csp/sentai/api/v1';
const TIMELAPSE = Number(process.env.SENTAI_MEDIA_TIMELAPSE ?? '1');
const SHOWCASE = JSON.parse(readFileSync(new URL('../../tests/fixtures/showcase-flow.json', import.meta.url), 'utf8'));
const MEDIA_NAME = 'Showcase + security (media)';

async function token(request: APIRequestContext): Promise<string> {
	const res = await request.post('/api/admin/login', {
		headers: { Authorization: `Basic ${Buffer.from(`${USER}:${PASSWORD}`).toString('base64')}` },
		data: {}
	});
	expect(res.status(), 'sign in for the recording').toBe(200);
	return (await res.json()).access_token;
}

/** The flow to film: the spec 011 showcase, plus a security report on each server when spec 013 is in. */
async function mediaFlow(request: APIRequestContext): Promise<{ id: string; reports: boolean }> {
	const auth = { Authorization: `Bearer ${await token(request)}` };
	const targets = await (await request.get(`${API}/targets`, { headers: auth })).json();
	expect(targets.some((t: { name: string; online: boolean }) => t.name === 'iris-target' && t.online), 'iris-target registered and online (FR-004)').toBe(true);
	const types = await (await request.get(`${API}/catalog/step-types`, { headers: auth })).json();
	const reports = types.some((t: { type: string; available: boolean }) => t.type === 'security-posture-report' && t.available);

	const def = structuredClone(SHOWCASE);
	def.name = reports ? MEDIA_NAME : SHOWCASE.name;
	if (reports) {
		const report = (id: string, target?: string) => ({
			id, type: 'security-posture-report', taskName: `Security posture${target ? ` on ${target}` : ''}`,
			namespace: '%SYS', wqmCategory: 'Default', timeoutMinutes: 10, parameters: {}, ...(target ? { target } : {})
		});
		def.steps.push(report('05'), report('06', 'iris-target'));
		def.edges.push({ source: '05', target: '04' }, { source: '06', target: '04' });
		def.canvasGeometry.nodes['05'] = { x: 40, y: 630 };
		def.canvasGeometry.nodes['06'] = { x: 40, y: 820 };
	}
	const flows = await (await request.get(`${API}/flows`, { headers: auth })).json();
	const existing = flows.find((f: { name: string }) => f.name === def.name);
	if (existing) return { id: String(existing.id), reports };
	const res = await request.post(`${API}/flows`, { headers: auth, data: def });
	expect(res.status(), await res.text()).toBe(201);
	return { id: String((await res.json()).id), reports };
}

async function caption(page: Page, scene: Scene) {
	const text = TIMELAPSE > 1.5 && scene === 'parallel' ? `${CAPTIONS[scene]} (time-lapse ×${TIMELAPSE.toFixed(1)})` : CAPTIONS[scene];
	await page.evaluate((t) => (window as unknown as { __caption: (s: string) => void }).__caption(t), text);
}

/** FR-003: no token, and (when it is not a common word) no password, anywhere on screen. */
async function assertNothingSecret(page: Page) {
	const kept = await page.evaluate(() => sessionStorage.getItem('sentai.signin'));
	const secrets = [kept ? (JSON.parse(kept).refreshToken as string) : null, PASSWORD.length >= 8 ? PASSWORD : null].filter(Boolean) as string[];
	const visible = await page.evaluate(() => {
		const inputs = [...document.querySelectorAll('input')].filter((i) => i.type !== 'password').map((i) => i.value);
		return `${document.body.innerText}\n${inputs.join('\n')}`;
	});
	for (const s of secrets) expect(visible.includes(s), 'a secret is visible on screen').toBe(false);
}

async function signIn(page: Page, query: string) {
	await page.addInitScript(() => {
		try {
			localStorage.setItem('sentai.guide.dismissed', '1');
		} catch {
			/* storage refused: the guide opens and is closed below */
		}
	});
	await page.goto(`/csp/sentai/index.html${query}`);
	await page.getByLabel('User').fill(USER);
	await page.getByLabel('Password').fill(PASSWORD);
	await page.getByRole('button', { name: 'Sign in' }).click();
}

test('showcase run — the recording (data-model §1)', async ({ page, request }, info) => {
	const { id, reports } = await mediaFlow(request);
	await page.addInitScript(CAPTION_INIT);
	await page.addInitScript(() => localStorage.setItem('sentai.theme', 'dark'));
	const marks: Record<string, number> = {};
	const mark = (scene: string) => (marks[scene] = Date.now());

	await signIn(page, `?flow=${id}`);
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	mark('flow');
	await caption(page, 'flow');
	await page.waitForTimeout(3000);

	mark('validate');
	await caption(page, 'validate');
	await page.getByRole('button', { name: 'Validate flow' }).click();
	// The button reads "Validating…" while the platform answers; the scene holds 2 s after that.
	await expect(page.getByRole('button', { name: 'Validate flow' })).toBeEnabled({ timeout: 30_000 });
	await page.waitForTimeout(2000);

	mark('run');
	await caption(page, 'run');
	await page.getByRole('button', { name: 'Run now' }).click();
	for (const field of await page.getByLabel(/^Password for/).all()) await field.fill(PASSWORD);
	await assertNothingSecret(page);
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
	await expect(page.getByTestId('run-state')).toBeVisible();

	mark('parallel');
	await caption(page, 'parallel');
	await expect(page.locator('.svelte-flow__node[data-id="04"]').getByTestId('state-chip')).toHaveText(/RUNNING|COMPLETED/, { timeout: 240_000 });
	mark('join');
	await caption(page, 'join');
	await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED', { timeout: 120_000 });
	// Real time after the time-lapse part: long enough to read the caption at the GIF's speed.
	await page.waitForTimeout(2500 * Math.max(1, TIMELAPSE));
	await assertNothingSecret(page);

	mark('result');
	await caption(page, 'result');
	await page.locator(`.svelte-flow__node[data-id="${reports ? '05' : '04'}"]`).getByRole('button', { name: 'Result' }).click();
	await expect(page.getByTestId('result-panel')).toBeVisible();
	await page.waitForTimeout(3500);
	await page.getByTestId('result-panel').getByRole('button', { name: 'Close' }).click();

	mark('log');
	await caption(page, 'log');
	await page.getByTestId('run-log').scrollIntoViewIfNeeded();
	await page.waitForTimeout(2500);

	mark('history');
	await caption(page, 'history');
	await page.getByRole('button', { name: 'Back to flow' }).click();
	await page.getByRole('banner').getByRole('button', { name: 'Runs' }).click();
	await expect(page.getByTestId('run-row').first()).toBeVisible();
	await page.waitForTimeout(3000);
	await assertNothingSecret(page);
	mark('end');

	writeFileSync(info.outputPath('marks.json'), JSON.stringify({ marks, reports }, null, 2));
});

const SCREENS = [
	{ name: 'palette', query: (flow: string) => `?flow=${flow}`, ready: (p: Page) => p.getByRole('heading', { name: 'STEP TYPES' }) },
	{ name: 'run-history', query: () => '?view=runs', ready: (p: Page) => p.getByTestId('run-row').first() },
	{ name: 'targets', query: () => '?view=targets', ready: (p: Page) => p.getByRole('heading', { name: 'Targets' }) },
	{ name: 'catalog', query: () => '?view=catalog', ready: (p: Page) => p.getByRole('heading', { name: 'Task catalog' }) }
];

for (const theme of ['dark', 'light'] as const) {
	test(`stills — ${theme}`, async ({ page, request }) => {
		const out = process.env.SENTAI_MEDIA_STILLS ?? 'media-results/stills';
		mkdirSync(out, { recursive: true });
		await page.setViewportSize({ width: 1440, height: 900 });
		const { id } = await mediaFlow(request);
		await page.addInitScript((t) => localStorage.setItem('sentai.theme', t), theme);
		await signIn(page, `?flow=${id}`);
		for (const s of SCREENS) {
			await page.goto(`/csp/sentai/index.html${s.query(id)}`);
			await expect(s.ready(page)).toBeVisible({ timeout: 30_000 });
			await page.waitForTimeout(800);
			await assertNothingSecret(page);
			await page.screenshot({ path: `${out}/${s.name}-${theme}.png` });
		}
		// The last completed run of the media flow, with a report open.
		const auth = { Authorization: `Bearer ${await token(request)}` };
		const runs = await (await request.get(`${API}/runs?flowId=${id}&state=completed&limit=1`, { headers: auth })).json();
		expect(runs.length, 'record the video first: it leaves a completed run').toBeGreaterThan(0);
		await page.goto(`/csp/sentai/index.html?flow=${id}&run=${runs[0].guid}`);
		await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED');
		await page.waitForTimeout(800);
		await page.screenshot({ path: `${out}/showcase-run-${theme}.png` });
		await page.locator('.svelte-flow__node[data-id="04"]').getByRole('button', { name: 'Result' }).click();
		await expect(page.getByTestId('result-panel')).toBeVisible();
		await page.screenshot({ path: `${out}/report-result-${theme}.png` });
	});
}
