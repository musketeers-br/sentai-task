import { describe, expect, it } from 'vitest';
import type { StepTypeInfo } from '$lib/flow/document';
import { RUNBOOKS } from './runbooks';
import { runbookCards } from './runbookCards';

// Spec 022 US3 (FR-005, FR-007; data-model §2): the pure card view model — verdicts derived from
// catalog and target data only, never a permission (Constitution III); the platform decides
// permission at create/run time and its refusal passes through verbatim (FR-009).

const base: StepTypeInfo[] = [
	{ type: 'integrity-check', label: 'Integrity check', className: '%SYS.Task.IntegrityCheck', category: 'verification', destructive: false, pausable: false, available: true, executor: 'platform-api' },
	{ type: 'switch-journal', label: 'Switch journal', className: '%SYS.Task.SwitchJournal', category: 'journal', destructive: false, pausable: false, available: true, executor: 'in-process' },
	{ type: 'purge-task-history', label: 'Purge task history', className: '%SYS.Task.PurgeTaskHistory', category: 'purge', destructive: true, pausable: false, available: true, executor: 'in-process' },
	{ type: 'storage-headroom-check', label: 'Storage headroom check', className: 'sentai.steps.StorageHeadroomCheck', category: 'storage', destructive: false, pausable: false, available: true, executor: 'in-process' },
	{ type: 'db-size-report', label: 'Database size report', className: 'sentai.steps.DatabaseSizeReport', category: 'verification', destructive: false, pausable: false, available: true, executor: 'in-process' },
	{ type: 'security-posture-report', label: 'Security posture report', className: 'sentai.steps.reports.SecurityPosture', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read' },
	{ type: 'web-app-inventory', label: 'Web application inventory', className: 'sentai.steps.reports.WebAppInventory', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read' },
	{ type: 'certificate-expiry-check', label: 'Certificate expiry check', className: 'sentai.steps.reports.CertificateExpiry', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read' },
	{ type: 'permissions-inventory', label: 'Permissions inventory', className: 'sentai.steps.reports.PermissionsInventory', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read' },
	{ type: 'oauth-inventory', label: 'OAuth inventory', className: 'sentai.steps.reports.OAuthInventory', category: 'security', destructive: false, pausable: false, available: true, executor: 'platform-read' }
];

const byTitle = (title: string) => RUNBOOKS.find((r) => r.title === title)!;

describe('runbookCards (FR-005, FR-007, data-model §2)', () => {
	it('marks a card runnable when every type is available and every target is registered', () => {
		const cards = runbookCards(RUNBOOKS, base, ['iris-target']);
		for (const card of cards) {
			expect(card.availability, card.runbook.title).toEqual({ kind: 'runnable' });
		}
	});

	it('names the step type when a type is not available on the instance', () => {
		const registry = base.map((t) => (t.type === 'purge-task-history' ? { ...t, available: false } : t));
		const weekly = runbookCards(RUNBOOKS, registry, []).find((c) => c.runbook.title === 'Weekly maintenance window')!;
		expect(weekly.availability).toEqual({
			kind: 'unavailable',
			reason: expect.stringContaining('Purge task history')
		});
	});

	it('names the type when it is not declared at all', () => {
		const registry = base.filter((t) => t.type !== 'db-size-report');
		const weekly = runbookCards(RUNBOOKS, registry, []).find((c) => c.runbook.title === 'Weekly maintenance window')!;
		expect(weekly.availability).toEqual({
			kind: 'unavailable',
			reason: expect.stringContaining('Db size report')
		});
	});

	it('names the target when a remote step needs a server that is not registered (FR-007)', () => {
		const cross = runbookCards(RUNBOOKS, base, []).find((c) => c.runbook.title === 'Cross-server nightly')!;
		expect(cross.availability).toEqual({
			kind: 'unavailable',
			reason: expect.stringContaining('iris-target')
		});
		// With the target registered the same card is runnable.
		const withTarget = runbookCards(RUNBOOKS, base, ['iris-target']).find((c) => c.runbook.title === 'Cross-server nightly')!;
		expect(withTarget.availability).toEqual({ kind: 'runnable' });
	});

	it('only the remote runbook is gated on targets; local ones stay runnable without any', () => {
		const cards = runbookCards(RUNBOOKS, base, []);
		for (const card of cards.filter((c) => c.runbook.title !== 'Cross-server nightly')) {
			expect(card.availability, card.runbook.title).toEqual({ kind: 'runnable' });
		}
	});

	it('carries the registry label, the destructive flag and the step target of every step', () => {
		const weekly = runbookCards(RUNBOOKS, base, []).find((c) => c.runbook.title === 'Weekly maintenance window')!;
		expect(weekly.steps.map((s) => s.label)).toEqual([
			'Storage headroom check',
			'Database size report',
			'Switch journal',
			'Integrity check',
			'Integrity check',
			'Purge task history'
		]);
		expect(weekly.steps.map((s) => s.destructive)).toEqual([false, false, false, false, false, true]);
		for (const step of weekly.steps) expect(step.onTarget).toBeNull();

		const cross = runbookCards(RUNBOOKS, base, ['iris-target']).find((c) => c.runbook.title === 'Cross-server nightly')!;
		expect(cross.steps[2].onTarget).toBe('iris-target');
	});

	it('echoes the suggested cadence so the card can show it as text (FR-004)', () => {
		const cards = runbookCards(RUNBOOKS, base, ['iris-target']);
		expect(cards.find((c) => c.runbook.title === 'Certificate expiry watch')!.cadence).toBe('daily');
		expect(cards.find((c) => c.runbook.title === 'Pre-upgrade checklist')!.cadence).toBeUndefined();
	});
});
