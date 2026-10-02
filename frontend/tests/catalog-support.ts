import { expect, type APIRequestContext, type Page } from '@playwright/test';
import {
	fromWireCatalogTask,
	originMark,
	statusLabel,
	type CatalogTaskView,
	type Value,
	type WireCatalogTask
} from '../src/lib/catalog/catalog';
import { token } from './support';

// What the catalog screens must read for each API value (spec 007 data-model.md).

export const catalog = (page: Page) => page.getByRole('region', { name: 'Task catalog' });
export const detail = (page: Page) => page.getByRole('region', { name: 'Task detail' });

/** A value, "unavailable — HTTP n — reason", or "—" for none reported / not returned. */
export function valueText(value: Value<string>, format: (v: string) => string = (v) => v): string {
	if (value.kind === 'unavailable') return `unavailable — HTTP ${value.reason.httpStatus} — ${value.reason.text}`;
	if (value.kind === 'absent' || value.value === '') return '—';
	return format(value.value);
}

const yesNo = (v: Value<boolean>): Value<string> => (v.kind === 'value' ? { kind: 'value', value: v.value ? 'yes' : 'no' } : v);

const DESTRUCTIVENESS = { yes: 'destructive', no: 'not destructive', unknown: 'destructiveness unknown' } as const;

/** The detail's text for each FR-006 field. */
export function detailText(task: CatalogTaskView): Record<string, string> {
	return {
		name: task.name,
		taskId: String(task.taskId),
		namespace: task.namespace,
		className: valueText(task.className),
		runAsUser: valueText(task.runAsUser),
		timePeriod: valueText(task.timePeriod),
		nextRun: valueText(task.nextRun),
		lastStarted: valueText(task.lastStarted),
		lastFinished: valueText(task.lastFinished),
		status: valueText(task.status, statusLabel),
		lastError: valueText(task.lastError),
		suspended: valueText(yesNo(task.suspended)),
		destructive: DESTRUCTIVENESS[task.destructive],
		origin: originMark(task)?.label ?? '—'
	};
}

export async function apiTask(request: APIRequestContext, taskId: number | string): Promise<{ wire: WireCatalogTask; view: CatalogTaskView }> {
	const res = await request.get(`/csp/sentai/api/v1/catalog/tasks/${taskId}`, {
		headers: { Authorization: `Bearer ${await token(request)}` }
	});
	expect(res.status(), await res.text()).toBe(200);
	const wire = (await res.json()) as WireCatalogTask;
	return { wire, view: fromWireCatalogTask(wire) };
}

/** Every FR-006 field of the open detail equals the API's item read; recent runs too. */
export async function expectDetail(page: Page, view: CatalogTaskView): Promise<Record<string, string>> {
	const pane = detail(page);
	await expect(pane.getByTestId('detail-field-taskId')).toHaveText(String(view.taskId));
	const expected = detailText(view);
	for (const [key, text] of Object.entries(expected)) {
		await expect(pane.getByTestId(`detail-field-${key}`), key).toHaveText(text);
	}
	if (view.recentRuns === undefined) {
		await expect(pane.getByRole('heading', { name: 'Recent runs' })).toHaveCount(0);
	} else if (view.recentRuns.length === 0) {
		await expect(pane.getByTestId('recent-runs')).toHaveText(/No run recorded\. This task has never executed on this instance\./);
	} else {
		await expect(pane.getByTestId('recent-run')).toHaveCount(view.recentRuns.length);
		for (const [i, run] of view.recentRuns.entries()) {
			await expect(pane.getByTestId('recent-run').nth(i)).toHaveText(
				[run.start, run.completed, run.status, run.result, run.user, run.loggedAt].join('')
			);
		}
	}
	return expected;
}
