// Spec 022: the curated runbook gallery — data, not code (Constitution II). Every definition is
// composed only of catalog step types with each declared parameter filled (FR-011); the set is
// fixed in the codebase and grows only through the ordinary change process (FR-002, Q1 answer A).
// The three definitions that also live in ObjectScript — the example (sentai.demo.Demo), the
// weekly window (sentai.demo.DemoFlows) and the cross-server showcase (sentai.demo.Demo again) —
// are compared with the shared fixtures from both sides: vitest here, DemoTest in the module, so
// neither side can drift alone (research R-2, data-model §7).
import type { ApiResult } from '$lib/api/client';
import type { FlowDefinition } from '$lib/flow/document';
import type { FlowSummaryView } from './list';
import { exampleDefinition } from './example';

/** One curated ready-made flow: the card (title, purpose, cadence) and the flow it opens. */
export interface Runbook {
	/** Card heading — the name the spec gives the runbook, in English (FR-017). */
	title: string;
	/** One line on the card: what this runbook is for (FR-003). */
	purpose: string;
	/** Suggested cadence, shown as text only; using a runbook never creates a schedule (FR-004). */
	suggestedCadence?: string;
	/**
	 * Identity: the flow name the platform's unique (case-insensitive) name index arbitrates.
	 * Use opens a flow of this name when one exists — on the demo that is the seeded flow —
	 * and otherwise creates one from `definition` (FR-006).
	 */
	flowName: string;
	/** The definition exactly as a create sends it to POST /flows; `name` is `flowName`. */
	definition: FlowDefinition;
}

/** A step of a definition, in the shipped key style (the showcase's): every field explicit. */
function step(
	id: string,
	type: string,
	taskName: string,
	namespace: string,
	parameters: Record<string, unknown>,
	timeoutMinutes: number,
	extra: { databaseDirectory?: string; target?: string } = {}
) {
	return { id, type, taskName, namespace, wqmCategory: 'Default', timeoutMinutes, parameters, ...extra };
}

/** The card's stable, derived id (`data-runbook`): lower-cased, runs of non-alphanumerics → `-`. */
export function runbookSlug(flowName: string): string {
	return flowName
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '');
}

/** The nightly sweep: integrity in parallel across the local namespaces, joined into one report. */
function nightlyIntegritySweep(): FlowDefinition {
	return {
		name: 'Nightly integrity sweep',
		defaultCategory: 'Default',
		steps: [
			step('01', 'integrity-check', 'Integrity check: USER', 'USER', {}, 45),
			step('02', 'integrity-check', 'Integrity check: IRISAPP', 'IRISAPP', {}, 45),
			step('03', 'db-size-report', 'Database size report', '%SYS', {}, 10)
		],
		edges: [
			{ source: '01', target: '03' },
			{ source: '02', target: '03' }
		],
		joins: [{ target: '03', policy: 'ALL_MUST_SUCCEED' }],
		canvasGeometry: {
			nodes: {
				'01': { x: 40, y: 40, width: 240 },
				'02': { x: 40, y: 250, width: 240 },
				'03': { x: 400, y: 145, width: 240 }
			}
		}
	};
}

/** The weekly window, exactly as the demo seed and weekly-window-flow.json ship it (R-2). */
function weeklyMaintenanceWindow(): FlowDefinition {
	return {
		name: 'Weekly maintenance window',
		defaultCategory: 'Default',
		steps: [
			step('01', 'storage-headroom-check', 'Storage headroom', '%SYS', { minFreePercent: 15 }, 10),
			{ id: '02', type: 'db-size-report', taskName: 'Database size report', namespace: '%SYS', timeoutMinutes: 10, wqmCategory: 'Default' },
			{ id: '03', type: 'switch-journal', taskName: 'Switch journal', namespace: '%SYS', timeoutMinutes: 5, wqmCategory: 'Default' },
			{ id: '04', type: 'integrity-check', taskName: 'Integrity check - USER', namespace: 'USER', timeoutMinutes: 45, wqmCategory: 'Default' },
			{ id: '05', type: 'integrity-check', taskName: 'Integrity check - %SYS', namespace: '%SYS', timeoutMinutes: 45, wqmCategory: 'Default' },
			step('06', 'purge-task-history', 'Purge task history', '%SYS', { keepDays: 30 }, 10)
		],
		edges: [
			{ source: '01', target: '03' },
			{ source: '02', target: '03' },
			{ source: '03', target: '04' },
			{ source: '03', target: '05' },
			{ source: '04', target: '06' },
			{ source: '05', target: '06' }
		],
		joins: [
			{ target: '03', policy: 'ALL_MUST_SUCCEED' },
			{ target: '06', policy: 'ALL_MUST_SUCCEED' }
		],
		canvasGeometry: {
			viewport: { x: 0, y: 40, zoom: 0.85 },
			nodes: {
				'01': { x: 0, y: 0, width: 240 },
				'02': { x: 0, y: 220, width: 240 },
				'03': { x: 340, y: 110, width: 240 },
				'04': { x: 680, y: 0, width: 240 },
				'05': { x: 680, y: 220, width: 240 },
				'06': { x: 1020, y: 110, width: 240 }
			}
		}
	};
}

/** The go/no-go reads before an upgrade, joined into a final size report (research R-10). */
function preUpgradeChecklist(): FlowDefinition {
	return {
		name: 'Pre-upgrade checklist',
		defaultCategory: 'Default',
		steps: [
			step('01', 'security-posture-report', 'Security posture report', '%SYS', { failOnFindings: false }, 10),
			step('02', 'web-app-inventory', 'Web application inventory', '%SYS', { failOnFindings: false }, 10),
			step('03', 'certificate-expiry-check', 'Certificate expiry check', '%SYS', { warnDays: 30 }, 10),
			step('04', 'db-size-report', 'Database size report', '%SYS', {}, 10)
		],
		edges: [
			{ source: '01', target: '04' },
			{ source: '02', target: '04' },
			{ source: '03', target: '04' }
		],
		joins: [{ target: '04', policy: 'ALL_MUST_SUCCEED' }],
		canvasGeometry: {
			nodes: {
				'01': { x: 40, y: 0, width: 240 },
				'02': { x: 40, y: 190, width: 240 },
				'03': { x: 40, y: 380, width: 240 },
				'04': { x: 420, y: 190, width: 240 }
			}
		}
	};
}

/** The watch: one read that fails while a certificate is inside its warning window. */
function certificateExpiryWatch(): FlowDefinition {
	return {
		name: 'Certificate expiry watch',
		defaultCategory: 'Default',
		steps: [step('01', 'certificate-expiry-check', 'Certificate expiry check', '%SYS', { warnDays: 30 }, 10)],
		edges: [],
		joins: [],
		canvasGeometry: { nodes: { '01': { x: 60, y: 60, width: 240 } } }
	};
}

/** Three independent read-only inventories of the security surface, run in one wave. */
function securityReview(): FlowDefinition {
	return {
		name: 'Security review',
		defaultCategory: 'Default',
		steps: [
			step('01', 'permissions-inventory', 'Permissions inventory', '%SYS', { failOnFindings: false }, 10),
			step('02', 'security-posture-report', 'Security posture report', '%SYS', { failOnFindings: false }, 10),
			step('03', 'oauth-inventory', 'OAuth inventory', '%SYS', { failOnFindings: false }, 10)
		],
		edges: [],
		joins: [],
		canvasGeometry: {
			nodes: {
				'01': { x: 40, y: 0, width: 240 },
				'02': { x: 40, y: 190, width: 240 },
				'03': { x: 40, y: 380, width: 240 }
			}
		}
	};
}

/** The distributed showcase, exactly as the demo seed and showcase-flow.json ship it (R-2). */
function crossServerNightly(): FlowDefinition {
	return {
		name: 'Showcase: nightly checks across servers',
		defaultCategory: 'Default',
		steps: [
			step('01', 'integrity-check', 'Integrity check: USER', 'USER', {}, 30, { databaseDirectory: '/usr/irissys/mgr/user/' }),
			step('02', 'integrity-check', 'Integrity check: IRISAPP', 'IRISAPP', {}, 30, { databaseDirectory: '/data/IRISAPP_DATA/' }),
			step('03', 'integrity-check', 'Integrity check: USER on iris-target', 'USER', {}, 30, { target: 'iris-target' }),
			step('04', 'db-size-report', 'Database size report', '%SYS', {}, 10)
		],
		edges: [
			{ source: '01', target: '04' },
			{ source: '02', target: '04' },
			{ source: '03', target: '04' }
		],
		joins: [{ target: '04', policy: 'ALL_MUST_SUCCEED' }],
		canvasGeometry: {
			nodes: {
				'01': { x: 40, y: 60 },
				'02': { x: 40, y: 250 },
				'03': { x: 40, y: 440 },
				'04': { x: 400, y: 250 }
			}
		}
	};
}

/**
 * The example flow as the seventh card (FR-013) — the guide's step 2 and the *Open flow…* dialog's
 * ready-made entry open it through the same Use machine as every other card.
 */
export const EXAMPLE_RUNBOOK: Runbook = {
	title: 'Example: storage health check',
	purpose: 'A small example of safe, read-only checks to run on this instance.',
	flowName: 'Example: storage health check',
	definition: exampleDefinition()
};

/**
 * The launch catalog: the six runbooks the spec names, then the example flow as the seventh card
 * (FR-002, FR-013; Q1 answer A). A fixed array in the codebase — the gallery is not
 * runtime-extensible (Constitution II).
 */
export const RUNBOOKS: readonly Runbook[] = [
	{
		title: 'Nightly integrity sweep',
		purpose: 'Integrity checks in parallel across namespaces, joined into one report.',
		suggestedCadence: 'nightly',
		flowName: 'Nightly integrity sweep',
		definition: nightlyIntegritySweep()
	},
	{
		title: 'Weekly maintenance window',
		purpose: 'Check storage, switch the journal, verify integrity, then purge old task history.',
		suggestedCadence: 'weekly',
		flowName: 'Weekly maintenance window',
		definition: weeklyMaintenanceWindow()
	},
	{
		title: 'Pre-upgrade checklist',
		purpose: 'The go/no-go reads before an upgrade: security posture, web apps, certificates.',
		flowName: 'Pre-upgrade checklist',
		definition: preUpgradeChecklist()
	},
	{
		title: 'Certificate expiry watch',
		purpose: 'Fail while any certificate is inside its 30-day expiry window.',
		suggestedCadence: 'daily',
		flowName: 'Certificate expiry watch',
		definition: certificateExpiryWatch()
	},
	{
		title: 'Security review',
		purpose: 'Three read-only inventories of the instance: permissions, posture, OAuth.',
		flowName: 'Security review',
		definition: securityReview()
	},
	{
		title: 'Cross-server nightly',
		purpose: 'The distributed showcase: integrity on both servers, joined into one report.',
		suggestedCadence: 'nightly',
		flowName: 'Showcase: nightly checks across servers',
		definition: crossServerNightly()
	},
	EXAMPLE_RUNBOOK
];

/** The flows API surface Use needs — the same shape `openExample` took (spec 010), so the page
 *  injects the real client and the tests inject fakes. */
export interface RunbookApi {
	listFlows(): Promise<ApiResult<FlowSummaryView[]>>;
	createFlow(def: FlowDefinition): Promise<ApiResult<{ id: string | null }>>;
}

/**
 * FR-006 (spec 010 FR-017 generalized, data-model §4): the id of the flow this runbook opens —
 * the one of that name if it exists, otherwise a new one created from the definition through the
 * ordinary flow-creation path under the operator's own sign-in. The platform's unique name index
 * is the only memory; every refusal is returned exactly as the platform gave it (FR-009).
 */
export async function useRunbook(api: RunbookApi, runbook: Runbook): Promise<ApiResult<string>> {
	const listed = await api.listFlows();
	if (!listed.ok) return listed;
	const wanted = runbook.flowName.toLowerCase();
	const existing = listed.value.find((f) => f.name.toLowerCase() === wanted);
	if (existing) return { ok: true, value: existing.id };

	const created = await api.createFlow(runbook.definition);
	if (created.ok) return { ok: true, value: created.value.id! };
	if (created.error.kind === 'problem' && created.error.status === 409) {
		const again = await api.listFlows();
		const match = again.ok ? again.value.find((f) => f.name.toLowerCase() === wanted) : null;
		if (match) return { ok: true, value: match.id };
	}
	return created;
}
