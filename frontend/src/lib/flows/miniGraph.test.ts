import { describe, expect, it } from 'vitest';
import type { FlowDefinition, StepTypeInfo } from '$lib/flow/document';
import { RUNBOOKS } from './runbooks';
import { miniGraph, VIEW } from './miniGraph';

// Spec 022 US1 (data-model §3): the pure geometry behind every card's mini-graph — scaled
// positions, border-anchored edges, registry labels, destructive flags. No DOM, no Svelte.

/** The catalog's view of the types the runbooks use (labels, destructive flags). */
const registry: StepTypeInfo[] = [
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

const byTitle = (title: string) => RUNBOOKS.find((r) => r.title === title)!.definition;
const inside = (value: number, max: number) => value >= -0.5 && value <= max + 0.5;

describe('miniGraph (FR-003, data-model §3)', () => {
	it('counts nodes and edges as the definition does — the card draws what will open', () => {
		const weekly = miniGraph(byTitle('Weekly maintenance window'), registry);
		expect(weekly.nodes).toHaveLength(6);
		expect(weekly.edges).toHaveLength(6);

		const review = miniGraph(byTitle('Security review'), registry);
		expect(review.nodes).toHaveLength(3);
		expect(review.edges).toHaveLength(0);
	});

	it('scales every node into the viewBox, preserving the relative layout', () => {
		const weekly = miniGraph(byTitle('Weekly maintenance window'), registry);
		const left = weekly.nodes.reduce((m, n) => Math.min(m, n.x), Infinity);
		const right = weekly.nodes.reduce((m, n) => Math.max(m, n.x + n.width), -Infinity);
		expect(inside(left, VIEW.width)).toBe(true);
		expect(inside(right, VIEW.width)).toBe(true);
		for (const node of weekly.nodes) {
			expect(inside(node.x, VIEW.width)).toBe(true);
			expect(inside(node.y + node.height, VIEW.height)).toBe(true);
		}
		// Source geometry: 01/02 at x=0, 06 at x=1020 — the columns survive the scaling.
		const at = (id: string) => weekly.nodes.find((n) => n.id === id)!;
		expect(at('03').x).toBeGreaterThan(at('01').x);
		expect(at('06').x).toBeGreaterThan(at('04').x);
		expect(at('04').y).toBeLessThan(at('05').y);
	});

	it('anchors an edge on the borders it crosses: right of the source, left of the target', () => {
		const weekly = miniGraph(byTitle('Weekly maintenance window'), registry);
		const at = (id: string) => weekly.nodes.find((n) => n.id === id)!;
		// 01 → 03 is the left column to the middle column (horizontal).
		const e0103 = weekly.edges[0]; // edges arrive in definition order: 01→03 first
		const one = at('01');
		const three = at('03');
		expect(e0103.from.x).toBeCloseTo(one.x + one.width, 6);
		expect(e0103.from.y).toBeGreaterThanOrEqual(one.y);
		expect(e0103.from.y).toBeLessThanOrEqual(one.y + one.height);
		expect(e0103.to.x).toBeCloseTo(three.x, 6);
		expect(e0103.to.y).toBeGreaterThanOrEqual(three.y);
		expect(e0103.to.y).toBeLessThanOrEqual(three.y + three.height);
	});

	it('anchors a same-column edge on the bottom of the source and the top of the target', () => {
		const stacked: FlowDefinition = {
			name: 'stacked',
			defaultCategory: 'Default',
			steps: [
				{ id: 'a', type: 'db-size-report', taskName: 'A', namespace: '%SYS' },
				{ id: 'b', type: 'db-size-report', taskName: 'B', namespace: '%SYS' }
			],
			edges: [{ source: 'a', target: 'b' }],
			joins: [],
			canvasGeometry: { nodes: { a: { x: 0, y: 0 }, b: { x: 0, y: 200 } } }
		};
		const graph = miniGraph(stacked, registry);
		const [a, b] = graph.nodes;
		expect(graph.edges).toHaveLength(1);
		expect(graph.edges[0].from.y).toBeCloseTo(a.y + a.height, 6);
		expect(graph.edges[0].from.x).toBeCloseTo(a.x + a.width / 2, 6);
		expect(graph.edges[0].to.y).toBeCloseTo(b.y, 6);
		expect(graph.edges[0].to.x).toBeCloseTo(b.x + b.width / 2, 6);
	});

	it('labels nodes with the registry label and carries the destructive flag', () => {
		const weekly = miniGraph(byTitle('Weekly maintenance window'), registry);
		const at = (id: string) => weekly.nodes.find((n) => n.id === id)!;
		expect(at('01').label).toBe('Storage headroom check');
		expect(at('03').label).toBe('Switch journal');
		expect(at('06').destructive).toBe(true); // purge-task-history
		expect(at('06').label).toBe('Purge task history');
		for (const node of weekly.nodes.filter((n) => n.id !== '06')) {
			expect(node.destructive).toBe(false);
		}
	});

	it('a single-step runbook yields one node, no edges, inside the viewBox', () => {
		const watch = miniGraph(byTitle('Certificate expiry watch'), registry);
		expect(watch.nodes).toHaveLength(1);
		expect(watch.edges).toHaveLength(0);
		expect(inside(watch.nodes[0].x + watch.nodes[0].width, VIEW.width)).toBe(true);
		expect(watch.nodes[0].label).toBe('Certificate expiry check');
	});
});
