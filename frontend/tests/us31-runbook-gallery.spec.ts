/// <reference types="node" />
import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import { deleteFlowWithRuns, EXAMPLE_FLOW_NAME, RUNBOOK_CREATED_NAMES } from './iris';
import { envelope, flowButton, flowMoreButton, PASSWORD, paletteEntry, seedFlow, signIn, signInAt, token, USER } from './support';
import { contrastFailures } from './theming';

// spec 022 — the runbook gallery replaces the empty canvas (FR-001…FR-012), and inherits us20's
// retired guarantees 1:1 (plan D-9): offered, idempotent, guarded, honest about unavailability.

const EVIDENCE = '../specs/022-runbook-gallery/evidence';
const API = '/csp/sentai/api/v1';
const FLOWS = `**${API}/flows`;

const TITLES = [
	'Nightly integrity sweep',
	'Weekly maintenance window',
	'Pre-upgrade checklist',
	'Certificate expiry watch',
	'Security review',
	'Cross-server nightly',
	'Example: storage health check'
];

const gallery = (page: Page) => page.getByTestId('runbook-gallery');
const card = (page: Page, slug: string) => page.locator(`[data-testid="runbook-card"][data-runbook="${slug}"]`);

/** GET /flows answers `[]` for the next `times` reads — the *Open flow…* dialog's "no saved
 *  flows" state, where its ready-made entry renders (us20's pattern, spec 010 FR-016b). */
async function emptyListFor(page: Page, times: number) {
	let left = times;
	await page.route(FLOWS, (route) => {
		if (route.request().method() === 'GET' && left > 0) {
			left--;
			return route.fulfill({ status: 200, json: [] });
		}
		return route.continue();
	});
}

async function listFlows(request: APIRequestContext): Promise<Array<{ id: string; name: string }>> {
	const res = await request.get(`${API}/flows`, { headers: { Authorization: `Bearer ${await token(request)}` } });
	expect(res.status()).toBe(200);
	return res.json();
}

/** The flows this feature's tests create (iris.ts guards the deletions); the seeded weekly
 *  window and showcase are opened by Use but never deleted. */
const CLEANABLE = [EXAMPLE_FLOW_NAME, ...RUNBOOK_CREATED_NAMES];

test.beforeEach(async ({ request }) => {
	for (const flow of await listFlows(request)) {
		if (CLEANABLE.some((n) => flow.name.toLowerCase() === n.toLowerCase())) deleteFlowWithRuns(flow.id, flow.name);
	}
});

test('us31 gallery — the empty canvas is seven named runbooks (FR-001, FR-002, FR-003)', async ({ page }) => {
	await signIn(page);
	await expect(gallery(page)).toBeVisible();
	await expect(gallery(page)).toHaveAccessibleName('Runbooks');
	await expect(page.getByTestId('runbook-card')).toHaveCount(7);

	// The launch catalog, in order — exactly the seven of FR-002/Q1 A, no more.
	expect(await page.locator('[data-testid="runbook-card"] h3').allInnerTexts()).toEqual(TITLES);

	// Every card: a purpose line, a mini-graph drawn from the definition, and a Use control.
	for (const slug of [
		'nightly-integrity-sweep',
		'weekly-maintenance-window',
		'pre-upgrade-checklist',
		'certificate-expiry-watch',
		'security-review',
		'showcase-nightly-checks-across-servers',
		'example-storage-health-check'
	]) {
		const one = card(page, slug);
		await expect(one).toBeVisible();
		await expect(one.locator('.purpose')).not.toBeEmpty();
		await expect(one.getByTestId('runbook-card-graph')).toBeVisible();
		await expect(one.getByTestId('runbook-card-use')).toBeVisible();
	}

	// The graphs draw what will open: node/edge counts equal the definitions (FR-003).
	await expect(card(page, 'weekly-maintenance-window').getByTestId('mini-node')).toHaveCount(6);
	await expect(card(page, 'weekly-maintenance-window').getByTestId('mini-edge')).toHaveCount(6);
	await expect(card(page, 'security-review').getByTestId('mini-node')).toHaveCount(3);
	await expect(card(page, 'security-review').getByTestId('mini-edge')).toHaveCount(0);

	// Suggested cadence is text, where declared (FR-004).
	await expect(card(page, 'weekly-maintenance-window').getByTestId('runbook-card-cadence')).toHaveText('Suggested: weekly');
	await expect(card(page, 'certificate-expiry-watch').getByTestId('runbook-card-cadence')).toHaveText('Suggested: daily');
	await expect(card(page, 'security-review').getByTestId('runbook-card-cadence')).toHaveCount(0);

	mkdirSync(EVIDENCE, { recursive: true });
	await page.screenshot({ path: `${EVIDENCE}/us31-gallery-dark.png` });
	await page.getByRole('button', { name: 'Light', exact: true }).click();
	await page.screenshot({ path: `${EVIDENCE}/us31-gallery-light.png` });
	await page.getByRole('button', { name: 'Dark', exact: true }).click();
	writeFileSync(`${EVIDENCE}/us31-gallery.json`, envelope('us31-gallery', { ui: 'runbook gallery' }, { cards: TITLES }, ['FR-001–FR-004 on the empty canvas.']));
});

test('us31 flows exist — the gallery is the empty canvas anyway (FR-001, SC-001)', async ({ page }) => {
	// A saved flow exists on the instance (the old invitation required none; that was the gap).
	const seeded = await listFlows(page.request);
	expect(seeded.length).toBeGreaterThan(0);
	await signIn(page);
	await expect(gallery(page)).toBeVisible();
	await expect(page.getByTestId('runbook-card')).toHaveCount(7);
});

test('us31 start from scratch — the gallery never blocks blank-canvas authoring (FR-012)', async ({ page }) => {
	await signIn(page);
	await gallery(page).getByTestId('start-from-scratch').click();
	await expect(gallery(page)).toHaveCount(0);

	// The palette works on the canvas the gallery left behind.
	await (await paletteEntry(page, 'db-size-report')).click();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(1);
});

test('us31 keyboard — the gallery is a labelled region, operable by keyboard alone (FR-016)', async ({ page }) => {
	await signIn(page);
	await expect(gallery(page)).toHaveAccessibleName('Runbooks');

	// Tab reaches a Use control and *Start from scratch* without a pointer.
	const use = page.getByTestId('runbook-card-use').first();
	const scratch = gallery(page).getByTestId('start-from-scratch');
	let focusedUse = false;
	let focusedScratch = false;
	for (let i = 0; i < 60 && !(focusedUse && focusedScratch); i++) {
		await page.keyboard.press('Tab');
		focusedUse ||= await use.evaluate((el) => document.activeElement === el);
		focusedScratch ||= await scratch.evaluate((el) => document.activeElement === el);
	}
	expect(focusedUse, 'Tab reaches a Use control').toBe(true);
	expect(focusedScratch, 'Tab reaches Start from scratch').toBe(true);
});

// --- User Story 2: Use puts a runnable flow on the canvas in one action (FR-006…FR-010) -------
// These own us20's retired guarantees 1:1 (plan D-9): run-to-completion, idempotence, guard.

test('us31 use — one action from the card to a running flow (FR-006, FR-010, SC-002)', async ({ page }) => {
	await signIn(page);
	const card = page.locator('[data-testid="runbook-card"][data-runbook="example-storage-health-check"]');
	await card.getByTestId('runbook-card-use').click();

	// The flow of that name is open on the canvas, its graph matching the card (FR-003/FR-006).
	await expect(page.getByLabel('Flow name')).toHaveValue(EXAMPLE_FLOW_NAME);
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toMatch(/^\d+$/);
	await expect(page.locator('.svelte-flow__node')).toHaveCount(2);
	await expect(page.locator('.svelte-flow__edge')).toHaveCount(0);

	// Validate flow checks it against the instance exactly like any flow.
	await flowButton(page, 'validate').click();
	await expect(page.getByRole('status').filter({ hasText: 'Flow is valid — no errors, no warnings.' })).toBeVisible();

	// Run now completes both read-only steps (the retired us20 run guarantee).
	await page.getByRole('button', { name: 'Run now' }).click();
	await expect(page.getByTestId('typed-confirmations')).toHaveCount(0);
	await page.getByLabel(`Password for ${USER}`).fill(PASSWORD);
	await page.getByRole('button', { name: 'Dispatch', exact: true }).click();
	const chip = (stepId: string) => page.locator(`.svelte-flow__node[data-id="${stepId}"]`).getByTestId('state-chip');
	await expect(chip('01')).toHaveText('COMPLETED', { timeout: 60_000 });
	await expect(chip('02')).toHaveText('COMPLETED', { timeout: 60_000 });
	await expect(page.getByTestId('run-state')).toHaveText('RUN COMPLETED', { timeout: 30_000 });
	writeFileSync(`${EVIDENCE}/us31-use.json`, envelope('us31-use', { ui: 'Use on the example card' }, { run: 'completed' }, ['The retired us20 run guarantee, via the gallery.']));
});

test('us31 idempotent — Use again opens the same flow; never a duplicate (FR-006, the us20 guarantee)', async ({ page }) => {
	await signIn(page);
	await page.locator('[data-testid="runbook-card"][data-runbook="example-storage-health-check"]').getByTestId('runbook-card-use').click();
	await expect(page.getByLabel('Flow name')).toHaveValue(EXAMPLE_FLOW_NAME);
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toMatch(/^\d+$/);
	const id = new URL(page.url()).searchParams.get('flow');

	// An edit is kept like any flow's.
	const node = page.locator('.svelte-flow__node[data-id="02"]');
	const box = (await node.boundingBox())!;
	await page.mouse.move(box.x + 30, box.y + 12);
	await page.mouse.down();
	await page.mouse.move(box.x + 30, box.y + 172, { steps: 8 });
	await page.mouse.up();
	await flowButton(page, 'save').click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');

	// The ready-made entry from Open flow… leads to the gallery, whose Use opens the same flow
	// (spec 022 FR-013 — the name index decides, never a duplicate).
	await flowMoreButton(page).click();
	await page.getByRole('menuitem', { name: 'New flow' }).click();
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toBeNull();
	await emptyListFor(page, 1);
	await flowButton(page, 'open').click();
	await page.getByRole('dialog', { name: 'Open flow' }).getByRole('button', { name: 'Browse runbooks' }).click();
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();
	await page.locator('[data-testid="runbook-card"][data-runbook="example-storage-health-check"]').getByTestId('runbook-card-use').click();
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toBe(id);
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');
	const flows = (await listFlows(page.request)).filter((f) => f.name.toLowerCase() === EXAMPLE_FLOW_NAME.toLowerCase());
	expect(flows.map((f) => f.id)).toEqual([id]);
});

test('us31 guard — the ready-made path over unsaved edits asks first (FR-008, the us20 guarantee)', async ({ page }) => {
	const name = `us31-guard-${Date.now()}`;
	const seeded = await seedFlow(page.request, {
		name,
		defaultCategory: 'Default',
		steps: [{ id: '01', type: 'db-size-report', taskName: 'Sizes', namespace: '%SYS', wqmCategory: 'Default' }],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 40, y: 40 } } }
	});
	await signInAt(page, `?flow=${seeded}`);
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	await (await paletteEntry(page, 'db-size-report')).click(); // unsaved edit

	// Spec 022 FR-013: the ready-made path is *Browse runbooks* — over unsaved edits it goes
	// through the same guard (FR-008).
	await emptyListFor(page, 1);
	await flowButton(page, 'open').click();
	await page.getByRole('dialog', { name: 'Open flow' }).getByRole('button', { name: 'Browse runbooks' }).click();
	const guard = page.getByRole('dialog', { name: /^Save changes to / });
	await expect(guard).toBeVisible();
	await guard.getByRole('button', { name: 'Cancel' }).click();
	await expect(page.locator('.svelte-flow__node')).toHaveCount(2);
	expect(new URL(page.url()).searchParams.get('flow')).toBe(seeded);
	expect((await listFlows(page.request)).filter((f) => f.name.toLowerCase() === EXAMPLE_FLOW_NAME.toLowerCase())).toEqual([]);

	// The guide's entry guards the same way; Discard leads on to the gallery (FR-013).
	await page.getByRole('banner').getByRole('button', { name: 'Help' }).click();
	await page.getByRole('menuitem', { name: 'Getting started' }).click();
	await page.getByRole('dialog', { name: 'Getting started' }).getByRole('button', { name: 'Next' }).click();
	await page.getByRole('dialog', { name: 'Getting started' }).getByRole('button', { name: 'Browse runbooks' }).click();
	await expect(guard).toBeVisible();
	await guard.getByRole('button', { name: 'Discard' }).click();
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();

	await deleteFlowWithRuns(seeded, name);
});

test('us31 refusal — the platform words surface verbatim and nothing is created (FR-009, SC-003)', async ({ page }) => {
	await page.route(FLOWS, (route) =>
		route.request().method() === 'POST'
			? route.fulfill({ status: 403, json: { status: 403, title: 'Forbidden', detail: 'not permitted (spec 022 probe)' } })
			: route.continue()
	);
	await signIn(page);
	await page.locator('[data-testid="runbook-card"][data-runbook="certificate-expiry-watch"]').getByTestId('runbook-card-use').click();
	await expect(page.getByRole('status').filter({ hasText: 'not permitted (spec 022 probe)' })).toBeVisible();
	await expect(page.getByTestId('runbook-gallery')).toBeVisible(); // the gallery stays usable
});

test('us31 weekly window — Use opens the seeded flow; destructive content is confirmed, not hidden (FR-005, FR-006, FR-010)', async ({ page }) => {
	await signIn(page);
	await page.locator('[data-testid="runbook-card"][data-runbook="weekly-maintenance-window"]').getByTestId('runbook-card-use').click();
	await expect(page.getByLabel('Flow name')).toHaveValue('Weekly maintenance window');
	await expect(page.locator('.svelte-flow__node')).toHaveCount(6);

	await flowButton(page, 'validate').click();
	await expect(page.getByRole('status').filter({ hasText: 'Flow is valid — no errors, no warnings.' })).toBeVisible();

	// Purge task history is destructive: the platform demands the typed confirmation, exactly as
	// for an operator-built flow. Cancel — nothing runs on the shared stack.
	await page.getByRole('button', { name: 'Run now' }).click();
	await expect(page.getByTestId('typed-confirmations')).toBeVisible();
	const dispatch = page.getByRole('dialog', { name: /Run Weekly maintenance window now/ });
	await expect(dispatch).toBeVisible();
	await dispatch.getByRole('button', { name: 'Cancel', exact: true }).click();
	await expect(dispatch).toBeHidden();
});

// --- User Story 3: cards tell the truth about the runbook (FR-004, FR-005, FR-007) -----------

test('us31 verdict — a remote runbook without its target is shown, not clickable, with the reason (FR-007, the us20 guarantee)', async ({ page }) => {
	await page.route(`**${API}/targets`, (route) => route.fulfill({ status: 200, json: [] }));
	await signIn(page);
	const cross = page.locator('[data-testid="runbook-card"][data-runbook="showcase-nightly-checks-across-servers"]');
	await expect(cross).toBeVisible();
	await expect(cross.getByTestId('runbook-card-use')).toBeDisabled();
	await expect(cross.getByTestId('runbook-card-reason')).toContainText('iris-target');
	// The card keeps its graph — the reason is honest, not hiding.
	await expect(cross.getByTestId('mini-node')).toHaveCount(4);

	// Local runbooks stay runnable on the same instance (only the remote card is gated).
	await expect(page.locator('[data-testid="runbook-card"][data-runbook="weekly-maintenance-window"]').getByTestId('runbook-card-use')).toBeEnabled();
});

test('us31 destructive — the weekly window card names its steps and marks the destructive one (FR-005)', async ({ page }) => {
	await signIn(page);
	const weekly = page.locator('[data-testid="runbook-card"][data-runbook="weekly-maintenance-window"]');
	await expect(weekly.locator('.steps li')).toHaveText([
		'Storage headroom check',
		'Database size report',
		'Switch journal',
		'Integrity check',
		'Integrity check',
		'Purge task history destructive'
	]);
	await expect(weekly.locator('.steps li.destructive')).toHaveText(['Purge task history destructive']);
	// The mini-graph carries the accent too (data-model §3).
	await expect(weekly.locator('[data-testid="mini-node"].destructive')).toHaveCount(1);
});

// --- User Story 4: the gallery fits in without displacing anything (FR-008, FR-012, FR-015, FR-016)

test('us31 precedence — a platform state never sits under the gallery (Constitution IV, edge cases)', async ({ page }) => {
	// A flow the address names but the platform refuses to read: the unreadable panel wins.
	await signInAt(page, '?flow=999999');
	await expect(page.getByTestId('flow-unreadable')).toBeVisible();
	await expect(page.getByTestId('runbook-gallery')).toHaveCount(0);

	// Not signed in: the sign-in screen, never the gallery.
	const fresh = await page.context().browser()?.newContext();
	const other = await fresh!.newPage();
	await other.goto('index.html?view=flows');
	await expect(other.getByRole('button', { name: 'Sign in' })).toBeVisible();
	await expect(other.getByTestId('runbook-gallery')).toHaveCount(0);
	await fresh!.close();
});

test('us31 tour — the three marks anchor over the gallery, which remains beneath and after (FR-015)', async ({ page }) => {
	await signIn(page);
	await expect(gallery(page)).toBeVisible();
	await page.getByTestId('tour-button').click();
	const tour = page.getByRole('dialog', { name: 'Tour' });
	await expect(tour.getByTestId('tour-indicator')).toHaveText('1 of 3');
	await expect(page.getByTestId('runbook-gallery')).toBeAttached();
	await tour.getByRole('button', { name: 'Next' }).click();
	await tour.getByRole('button', { name: 'Next' }).click();
	await tour.getByRole('button', { name: 'Done' }).click();
	await expect(tour).toHaveCount(0);
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();
});

test('us31 shared account — a used runbook reopens as the same flow, edits intact (scenario 4.5)', async ({ page }) => {
	await signIn(page);
	await page.locator('[data-testid="runbook-card"][data-runbook="certificate-expiry-watch"]').getByTestId('runbook-card-use').click();
	await expect(page.getByLabel('Flow name')).toHaveValue('Certificate expiry watch');
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toMatch(/^\d+$/);
	const id = new URL(page.url()).searchParams.get('flow');

	// An edit, kept by Save like any flow's.
	const node = page.locator('.svelte-flow__node[data-id="01"]');
	const box = (await node.boundingBox())!;
	await page.mouse.move(box.x + 30, box.y + 12);
	await page.mouse.down();
	await page.mouse.move(box.x + 30, box.y + 150, { steps: 6 });
	await page.mouse.up();
	await flowButton(page, 'save').click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');

	// The next visitor of the shared account: a fresh arrival at the Flows screen — the same
	// card opens the same flow, edits intact (the name index decides, never a duplicate).
	await page.getByRole('button', { name: 'Sign out' }).click();
	await page.goto('index.html?view=flows');
	await page.getByLabel('User').fill(USER);
	await page.getByLabel('Password').fill(PASSWORD);
	await page.getByRole('button', { name: 'Sign in' }).click();
	await expect(page.getByRole('heading', { name: 'STEP TYPES' })).toBeVisible();
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();
	await page.locator('[data-testid="runbook-card"][data-runbook="certificate-expiry-watch"]').getByTestId('runbook-card-use').click();
	await expect.poll(() => new URL(page.url()).searchParams.get('flow')).toBe(id);
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');
	const same = (await listFlows(page.request)).filter((f) => f.name === 'Certificate expiry watch');
	expect(same.map((f) => f.id)).toEqual([id]);
});

test('us31 keyboard use — Enter on the focused Use opens the flow (FR-016)', async ({ page }) => {
	await signIn(page);
	const use = page.locator('[data-testid="runbook-card"][data-runbook="weekly-maintenance-window"]').getByTestId('runbook-card-use');
	let focused = false;
	for (let i = 0; i < 60 && !focused; i++) {
		await page.keyboard.press('Tab');
		focused = await use.evaluate((el) => document.activeElement === el);
	}
	expect(focused, 'Tab reaches the weekly window Use').toBe(true);
	await page.keyboard.press('Enter');
	await expect(page.getByLabel('Flow name')).toHaveValue('Weekly maintenance window');
});

test('us31 theming — the cards read in both themes (FR-016, contrast)', async ({ page }) => {
	await signIn(page);
	const failures: Record<string, unknown> = {};
	for (const theme of ['Dark', 'Light'] as const) {
		await page.getByRole('button', { name: theme, exact: true }).click();
		await page.mouse.move(0, 0);
		const found = await contrastFailures(page);
		if (found.length > 0) failures[theme] = found;
		await page.screenshot({ path: `${EVIDENCE}/us31-cards-${theme.toLowerCase()}.png` });
	}
	expect(Object.keys(failures)).toEqual([]);
});

// --- User Story 5: one ready-made path, not two (FR-013) --------------------------------------

test('us31 one path — the guide and Open flow… offer Browse runbooks; the lone example is gone (FR-013)', async ({ page }) => {
	// From the guide: step 2's button lands on the gallery.
	await signIn(page, '', { guide: 'fresh' });
	const guideDialog = page.getByRole('dialog', { name: 'Getting started' });
	await expect(guideDialog).toBeVisible();
	await guideDialog.getByRole('button', { name: 'Next' }).click();
	await guideDialog.getByRole('button', { name: 'Browse runbooks' }).click();
	await expect(guideDialog).toHaveCount(0);
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();

	// From Open flow…: the empty-state entry lands on the gallery too.
	await emptyListFor(page, 1);
	await flowButton(page, 'open').click();
	const dialog = page.getByRole('dialog', { name: 'Open flow' });
	await dialog.getByRole('button', { name: 'Browse runbooks' }).click();
	await expect(dialog).toHaveCount(0);
	await expect(page.getByTestId('runbook-gallery')).toBeVisible();

	// No path offers a lone example anymore, and the example is one card among seven.
	await expect(page.getByRole('button', { name: 'Open example flow' })).toHaveCount(0);
	await expect(page.locator('[data-testid="runbook-card"][data-runbook="example-storage-health-check"]')).toBeVisible();
	await expect(page.getByTestId('runbook-card')).toHaveCount(7);
});
