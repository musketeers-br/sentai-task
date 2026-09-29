/// <reference types="node" />
import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { readRun, runToEnd, seedQuickFlow } from './runs-support';
// The run view opens straight from the address, so the sign-in must not wait for the editor.
import { signInAt as signIn } from './support';

// spec 012 User Story 3 — export a run (FR-013, FR-014, SC-005).

test('us26 — Export saves the run as the view shows it, and nothing from the session', async ({ page, request }) => {
	const name = `us26-export ${Date.now()}`;
	const id = await seedQuickFlow(request, name);
	const run = await runToEnd(request, id);
	await signIn(page, `?flow=${id}&run=${run.guid}`);
	await expect(page.getByTestId('run-state')).toContainText('RUN COMPLETED');

	const download = page.waitForEvent('download');
	await page.getByTestId('export-run').click();
	const file = await download;
	expect(file.suggestedFilename()).toBe(`${name.replace(/[^A-Za-z0-9._-]+/g, '-')}-${run.guid.slice(0, 8)}.json`);
	const text = readFileSync(await file.path(), 'utf8');
	const exported = JSON.parse(text);

	const api = (await readRun(request, run.guid)) as {
		steps: Array<{ stepId: string; state: string; failureReason: string; result: unknown }>;
		log: Array<{ message: string }>;
	};
	expect(exported.format).toBe('sentai-run-export/1');
	expect(exported.run.guid).toBe(run.guid);
	expect(exported.flow.name).toBe(name);
	expect(exported.steps.map((s: { stepId: string; state: string }) => [s.stepId, s.state])).toEqual(
		api.steps.map((s) => [s.stepId, s.state]).sort()
	);
	// The report each step stored travels with it.
	expect(exported.steps.find((s: { stepId: string }) => s.stepId === '02').result).toEqual(api.steps.find((s) => s.stepId === '02')!.result);
	// Oldest first in the file; the API is newest first.
	expect(exported.log.map((l: { message: string }) => l.message)).toEqual(api.log.map((l) => l.message).reverse());
	expect(text).not.toMatch(/access_token|refresh|password/i);
});
