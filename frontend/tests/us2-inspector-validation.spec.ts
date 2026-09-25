import { writeFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { canonicalFlow, envelope, EVIDENCE_DIR, seedFlow, signIn, v1Flow } from './support';

// spec.md User Story 2 — Inspector and Validation (Q3 + Q4).

test('Q3 — the inspector shows the bound sections and edits the step', async ({ page, request }) => {
	const id = await seedFlow(request, canonicalFlow(`Q3 inspector ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	await page.locator('.svelte-flow__node[data-id="04"] h3').click();
	const inspector = page.getByLabel('Inspector');

	// FR-014: sections in this exact order.
	await expect(inspector.locator('h2')).toHaveText([
		'SELECTED STEP',
		'IDENTIFICATION',
		'PARAMETERS',
		'DESTRUCTIVE STEP',
		'OUTPUT'
	]);

	// FR-016: real inputs with real labels.
	await expect(inspector.getByLabel('TaskName')).toHaveValue('Purge audit records');
	await expect(inspector.getByLabel('Namespace')).toHaveValue('%SYS');
	await expect(inspector.getByLabel('Run as user')).toHaveValue('irisadm');
	await expect(inspector.getByLabel('DaysToKeep')).toHaveValue('30');
	await expect(inspector.getByLabel('Timeout (min)')).toHaveValue('20');
	await expect(inspector.getByLabel('WQM category')).toHaveValue('Default');

	// Scenario 2 / FR-011: consequence in plain words and the checked typed-confirmation control.
	await expect(inspector).toContainText('Permanently removes audit records older than 30 days.');
	const confirm = inspector.getByLabel('Require the database name to be typed before running');
	await expect(confirm).toBeChecked();
	await expect(confirm).toBeDisabled();

	// FR-015: where the step's GUID lands.
	await expect(inspector.getByTestId('guid-destination')).toHaveText('step04.guid → ^sentaiRun(runGuid,"04")');

	// Editing reaches the node and persists as a new revision.
	await inspector.getByLabel('TaskName').fill('Purge audit records — 30 days');
	await inspector.getByLabel('Timeout (min)').fill('25');
	const node = page.locator('.svelte-flow__node[data-id="04"]');
	await expect(node).toContainText('Purge audit records — 30 days');
	await expect(node).toContainText('timeout 25 min');
	await page.screenshot({ path: `${EVIDENCE_DIR}/q3-inspector.png` });

	await page.getByRole('button', { name: 'Save flow' }).click();
	await expect(page.getByTestId('flow-meta')).toContainText('rev 2');
});

test('Q4 — validation reports errors and warnings; only errors block scheduling', async ({ page, request }) => {
	// A v1-runnable flow, so the only findings are the two this test plants.
	const flow = v1Flow(`Q4 validation ${Date.now()}`);
	flow.steps[1] = { ...flow.steps[1], namespace: 'DOCBOOK', taskName: 'Integrity check — DOCBOOK' };
	flow.steps[2] = { ...flow.steps[2], databaseDirectory: '/data/READONLY_DEMO/' };
	const id = await seedFlow(request, flow);
	await signIn(page, `?flow=${id}`);

	const validateCall = page.waitForResponse((r) => r.url().endsWith(`/flows/${id}/validate`));
	await page.getByRole('button', { name: 'Validate flow' }).click();
	const response = await validateCall;
	const report = await response.json();
	writeFileSync(
		`${EVIDENCE_DIR}/q4-validation-report.json`,
		envelope(
			'q4-validation-report',
			{ method: 'POST', url_path: `/csp/sentai/api/v1/flows/${id}/validate` },
			{ status: response.status(), body: report },
			['#02 namespace DOCBOOK does not exist on the dev image → error', '#03 points at the read-only fixture /data/READONLY_DEMO/ → warning']
		)
	);
	expect(report.errors.length).toBeGreaterThanOrEqual(1);
	expect(report.warnings.length).toBeGreaterThanOrEqual(1);

	// FR-008 / FR-009: warning panel on the node, counts in the status bar in the bound format.
	await expect(page.getByTestId('status-warnings')).toHaveText('1 precondition not met (#03)');
	await expect(page.getByTestId('status-errors')).toHaveText('1 error blocks scheduling (#02)');
	const readOnly = page.locator('.svelte-flow__node[data-id="03"]');
	await expect(readOnly.getByTestId('precondition-warning')).toContainText('Precondition not met');
	await expect(readOnly.getByTestId('precondition-warning')).toContainText('Database mounted read-only.');
	await expect(page.locator('.svelte-flow__node[data-id="02"]').getByTestId('validation-error')).toContainText(
		"Namespace 'DOCBOOK' does not exist on this instance"
	);
	const schedule = page.getByRole('button', { name: 'Schedule in Task Manager' });
	await expect(schedule).toBeDisabled();
	await page.screenshot({ path: `${EVIDENCE_DIR}/q4-status-bar.png` });

	// Fixing the error re-enables scheduling; the remaining warning does not block it (FR-010).
	await page.locator('.svelte-flow__node[data-id="02"] h3').click();
	await page.getByLabel('Inspector').getByLabel('Namespace').fill('USER');
	await page.getByRole('button', { name: 'Validate flow' }).click();
	await expect(page.getByTestId('status-errors')).toHaveCount(0);
	await expect(page.getByTestId('status-warnings')).toHaveText('1 precondition not met (#03)');
	await expect(schedule).toBeEnabled();
});

test('Q4 (spec 004) — steps of types unsupported in v1 are refused at validation, named', async ({ page, request }) => {
	const id = await seedFlow(request, canonicalFlow(`Q4 unsupported ${Date.now()}`));
	await signIn(page, `?flow=${id}`);

	await page.getByRole('button', { name: 'Validate flow' }).click();
	await expect(page.getByTestId('status-errors')).toHaveText('2 errors block scheduling (#04, #05)');
	await expect(page.locator('.svelte-flow__node[data-id="04"]').getByTestId('validation-error')).toContainText(
		"Step type 'purge-audit-records' is not supported on the target platform in v1"
	);
	await expect(page.locator('.svelte-flow__node[data-id="05"]').getByTestId('validation-error')).toContainText(
		"Step type 'switch-journal' is not supported on the target platform in v1"
	);
	await expect(page.getByRole('button', { name: 'Schedule in Task Manager' })).toBeDisabled();
});
