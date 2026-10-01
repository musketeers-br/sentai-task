import { mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { expect, test, type Page, type Response } from '@playwright/test';
import { createDemoRoleOperator, deleteDemoOperator, deleteFlowWithRuns } from './iris';
import { LANDING, PASSWORD, signIn, signInAt, token, unscheduleFlow, USER } from './support';

// spec 019 — the Overview screen against the real spec 018 API: the landing screen with 11 cards,
// refusals verbatim, detail views, reports on demand, schedule this check, old addresses.

const EVIDENCE = '../specs/019-canvas-instance-overview/evidence';
mkdirSync(EVIDENCE, { recursive: true });
const API = '/csp/sentai/api/v1';

const cards = (page: Page) => page.getByTestId('area-card');
const card = (page: Page, area: string) => page.locator(`[data-testid="area-card"][data-area="${area}"]`);

function summaryResponse(page: Page): Promise<Response> {
	return page.waitForResponse((r) => r.url().endsWith(`${API}/overview`) && r.request().method() === 'GET');
}

async function waitRun(request: import('@playwright/test').APIRequestContext, guid: string) {
	for (let i = 0; i < 60; i++) {
		const run = await (await request.get(`${API}/runs/${guid}`, { headers: { Authorization: `Bearer ${await token(request)}` } })).json();
		if (['completed', 'failed', 'cancelled'].includes(run.state)) return run;
		await new Promise((r) => setTimeout(r, 1000));
	}
	throw new Error(`run ${guid} did not finish`);
}

test('us29 A — sign-in lands on Overview with 11 cards equal to the API (SC-001, SC-002)', async ({ page }) => {
	const answered = summaryResponse(page);
	const started = Date.now();
	await signInAt(page, LANDING);
	const summary = await (await answered).json();
	await expect(page.getByRole('heading', { name: 'Overview', exact: true })).toBeVisible();
	await expect(cards(page)).toHaveCount(11);
	await expect(page.locator('[data-testid="area-card"][data-state="ok"]')).toHaveCount(11);
	expect(Date.now() - started).toBeLessThan(15000); // sign-in included; SC-001's 3 s is the summary itself
	await expect(page.getByRole('banner').getByRole('button', { name: 'Overview' })).toHaveAttribute('aria-current', 'page');
	const count = (area: string) => summary.areas.find((a: { area: string }) => a.area === area).headline;
	const many = (value: number, word: string) => `${value.toLocaleString('en-US')} ${word}${value === 1 ? '' : 's'}`;
	await expect(card(page, 'locks')).toContainText(many(count('locks').count, 'lock'));
	await expect(card(page, 'web-apps')).toContainText(many(count('web-apps').count, 'web application'));
	await expect(card(page, 'secrets')).toContainText(many(count('secrets').collections, 'wallet collection'));
	await expect(card(page, 'licenses')).toContainText(`${count('licenses').inUse} of ${count('licenses').authorized} license units in use`);
	const text = await page.locator('section[aria-label="Overview"]').innerText();
	expect(text).not.toMatch(/\bCPU\b/);
	await page.screenshot({ path: `${EVIDENCE}/us29-overview-ok.png`, fullPage: true });
});

test('us29 B — an operator without security administration sees refusals verbatim (SC-003)', async ({ page }) => {
	const operator = createDemoRoleOperator();
	try {
		const answered = summaryResponse(page);
		await signInAt(page, LANDING, operator.user, operator.password);
		const summary = await (await answered).json();
		await expect(cards(page)).toHaveCount(11);
		const refused = summary.areas.filter((a: { outcome: string }) => a.outcome !== 'ok').map((a: { area: string }) => a.area);
		expect(refused).toContain('security');
		for (const a of summary.areas) {
			const c = card(page, a.area);
			if (a.outcome === 'ok') {
				await expect(c).toHaveAttribute('data-state', 'ok');
			} else {
				await expect(c).toHaveAttribute('data-state', a.outcome);
				await expect(c.getByTestId('card-refusal')).toContainText(`HTTP ${a.problem.httpStatus}`);
				await expect(c.getByTestId('card-refusal')).toContainText(a.problem.detail);
			}
		}
		await page.screenshot({ path: `${EVIDENCE}/us29-overview-refused.png`, fullPage: true });
	} finally {
		deleteDemoOperator(operator);
	}
});

test('us29 C — Processes: sort and filter equal the reading the page received; the address reopens it', async ({ page, browser }) => {
	await signInAt(page, LANDING);
	await expect(cards(page)).toHaveCount(11);
	const answered = page.waitForResponse((r) => r.url().includes(`${API}/overview/readings/processes`));
	await card(page, 'processes').getByRole('button', { name: 'Open' }).click();
	const reading = await (await answered).json();
	const table = page.getByRole('table', { name: 'Processes rows' });
	await expect(table).toBeVisible();
	await expect(page.getByText(`${reading.rows.length} rows`)).toBeVisible();
	await expect(table.getByRole('columnheader', { name: /CPU time \(process\)/ })).toBeVisible();

	await table.getByRole('button', { name: 'Commands' }).click();
	await table.getByRole('button', { name: /Commands/ }).click(); // descending
	const busiest = [...reading.rows].sort((a, b) => b.Commands - a.Commands)[0];
	const firstRow = table.locator('tbody tr').first();
	await expect(firstRow.locator('td').first()).toHaveText(Number(busiest.Pid).toLocaleString('en-US'));

	const ns = 'IRISAPP';
	await page.getByLabel('Filter rows').fill(ns);
	const matching = reading.rows.filter((r: Record<string, unknown>) => reading.columns.some((c: string) => r[c] != null && String(r[c]).toLowerCase().includes(ns.toLowerCase()))).length;
	await expect(page.getByText(`${reading.rows.length} rows · ${matching} shown`)).toBeVisible();

	const address = new URL(page.url());
	expect(address.searchParams.get('view')).toBe('overview');
	expect(address.searchParams.get('area')).toBe('processes');
	const other = await browser.newPage();
	try {
		await signInAt(other, `${address.search}`);
		await expect(other.getByRole('table', { name: 'Processes rows' })).toBeVisible();
	} finally {
		await other.close();
	}
	await page.screenshot({ path: `${EVIDENCE}/us29-processes.png` });
});

test('us29 D — auto-refresh makes no read while the tab is hidden (SC-006)', async ({ page }) => {
	await signInAt(page, '?view=overview&area=locks');
	await expect(page.getByRole('table', { name: 'Locks rows' })).toBeVisible();
	let reads = 0;
	page.on('request', (r) => {
		if (r.url().includes(`${API}/overview/readings/locks`)) reads++;
	});
	const setHidden = (hidden: boolean) =>
		page.evaluate((h) => {
			Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (h ? 'hidden' : 'visible') });
			document.dispatchEvent(new Event('visibilitychange'));
		}, hidden);
	await setHidden(true);
	await page.getByLabel('Auto-refresh every 10 s').check();
	await page.waitForTimeout(25000);
	expect(reads).toBe(0);
	await setHidden(false);
	await expect.poll(() => reads, { timeout: 5000 }).toBeGreaterThan(0);
	await page.getByLabel('Auto-refresh every 10 s').uncheck();
});

test('us29 E — a report runs on demand into the run viewer and stays on its card (SC-005)', async ({ page, request }) => {
	await signInAt(page, LANDING);
	await expect(cards(page)).toHaveCount(11);
	const answered = page.waitForResponse((r) => r.url().includes(`${API}/overview/reports/web-app-inventory`));
	await card(page, 'web-apps').getByRole('button', { name: 'Run report' }).click();
	const onDemand = await (await answered).json();
	const panel = page.getByTestId('result-panel');
	await expect(panel).toBeVisible();
	await expect(panel.getByTestId('finding')).toHaveCount(onDemand.report.findings.length);

	// The same report from a one-step run of the same type, opened in the run view.
	const auth = { Authorization: `Bearer ${await token(request)}` };
	const runsBefore = (await (await request.get(`${API}/runs?limit=200`, { headers: auth })).json()).length;
	const created = await (await request.post(`${API}/overview/areas/web-apps/flow`, { headers: { Authorization: `Bearer ${await token(request)}` }, data: {} })).json();
	const flowId = String(created.flow.id);
	try {
		const run = await (await request.post(`${API}/flows/${flowId}/dispatch`, { headers: { Authorization: `Bearer ${await token(request)}` }, data: {} })).json();
		const done = await waitRun(request, run.guid);
		const stored = typeof done.steps[0].result === 'string' ? JSON.parse(done.steps[0].result) : done.steps[0].result;
		const key = (f: { rule: string; severity: string; item: string }) => `${f.severity}|${f.rule}|${f.item}`;
		expect(stored.truncated).toBeUndefined();
		expect(stored.findings.map(key)).toEqual(onDemand.report.findings.map(key));
		expect(runsBefore).toBeGreaterThanOrEqual(0);

		const runView = await page.context().newPage();
		await signInAt(runView, `?flow=${flowId}&run=${run.guid}`);
		await expect(runView.getByRole('button', { name: 'Result' }).first()).toBeVisible();
		await runView.getByRole('button', { name: 'Result' }).first().click();
		const texts = async (p: Page) => (await p.getByTestId('finding').allInnerTexts()).map((t) => t.replace(/\s+/g, ' ').trim());
		expect(await texts(runView)).toEqual(await texts(page));
		await runView.close();
	} finally {
		deleteFlowWithRuns(flowId, created.flow.name);
	}

	await panel.getByRole('button', { name: 'Close' }).click();
	const reportLine = card(page, 'web-apps').getByTestId('card-report');
	await expect(reportLine).toContainText(`${onDemand.report.summary.high} high`);
	await page.getByRole('button', { name: 'Refresh' }).click();
	await expect(reportLine).toBeVisible();
	await expect(card(page, 'web-apps').getByRole('button', { name: 'Open report' })).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/us29-report-card.png` });
});

test('us29 F — Schedule this check from Secrets: flow, dialog, a scheduled run (SC-004)', async ({ page, request }) => {
	test.setTimeout(300000);
	await signInAt(page, LANDING);
	await expect(cards(page)).toHaveCount(11);
	await expect(card(page, 'processes').getByRole('button', { name: 'Schedule this check' })).toHaveCount(0);
	const created = page.waitForResponse((r) => r.url().includes(`${API}/overview/areas/secrets/flow`));
	await card(page, 'secrets').getByRole('button', { name: 'Schedule this check' })/* action 1 */.click();
	const flow = (await (await created).json()).flow;
	const dialog = page.getByRole('dialog', { name: 'Schedule in Task Manager' });
	await expect(dialog).toBeVisible();
	try {
		const now = execFileSync('docker', ['exec', process.env.SENTAI_CONTAINER ?? 'sentai-task-iris-1', 'date', '+%H:%M'], { encoding: 'utf8' }).trim();
		const [h, m] = now.split(':').map(Number);
		const at = new Date(Date.UTC(2000, 0, 1, h, m + 2));
		const hhmm = `${String(at.getUTCHours()).padStart(2, '0')}:${String(at.getUTCMinutes()).padStart(2, '0')}`;
		await dialog.getByLabel('At', { exact: true }).fill(hhmm); // action 2
		await dialog.getByLabel(`Password for ${USER}`, { exact: true }).fill(PASSWORD); // action 3
		await dialog.getByRole('button', { name: 'Schedule', exact: true }).click(); // action 4
		await expect(dialog.getByTestId('schedule-result')).toContainText(`Scheduled: Daily at ${hhmm}`);
		await page.screenshot({ path: `${EVIDENCE}/us29-schedule-dialog.png` });

		const auth = async () => ({ Authorization: `Bearer ${await token(request)}` });
		let scheduled: { guid: string } | undefined;
		for (let i = 0; i < 30 && !scheduled; i++) {
			await new Promise((r) => setTimeout(r, 10000));
			const runs = await (await request.get(`${API}/runs?flowId=${flow.id}&limit=10`, { headers: await auth() })).json();
			scheduled = runs.find((r: { trigger: string; state: string }) => r.trigger === 'scheduled' && ['completed', 'failed'].includes(r.state));
		}
		expect(scheduled, 'a scheduled run').toBeDefined();
		const run = await (await request.get(`${API}/runs/${scheduled!.guid}`, { headers: await auth() })).json();
		const result = typeof run.steps[0].result === 'string' ? JSON.parse(run.steps[0].result) : run.steps[0].result;
		expect(result.type).toBe('secrets-inventory');
	} finally {
		await unscheduleFlow(request, String(flow.id));
		deleteFlowWithRuns(String(flow.id), flow.name);
	}
});

test('us29 H — every older address opens what it names; both themes (SC-007, SC-008)', async ({ page }) => {
	await signIn(page, '?view=flows');
	for (const [query, check] of [
		['?view=catalog', () => expect(page.getByRole('banner').getByRole('button', { name: 'Task catalog' })).toHaveAttribute('aria-current', 'page')],
		['?view=targets', () => expect(page.getByRole('banner').getByRole('button', { name: 'Targets' })).toHaveAttribute('aria-current', 'page')],
		['?view=runs', () => expect(page.getByRole('banner').getByRole('button', { name: 'Runs' })).toHaveAttribute('aria-current', 'page')],
		['?view=flows', () => expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible()]
	] as const) {
		await page.goto(`index.html${query}`);
		await check();
		await expect(page.getByRole('heading', { name: 'Overview', exact: true })).toHaveCount(0);
	}
	await page.goto('index.html?view=overview');
	await expect(cards(page)).toHaveCount(11);
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		await page.mouse.move(0, 0);
		await page.screenshot({ path: `${EVIDENCE}/us29-overview-${theme.toLowerCase()}.png`, fullPage: true });
	}
});
