import { describe, expect, it } from 'vitest';
import { hasResult, isReport, orderedFindings, severityLabel, summaryLine, type Report } from './result';

const report: Report = {
	type: 'security-posture-report',
	instance: 'local',
	summary: { high: 2, medium: 1, info: 1 },
	findings: [
		{ severity: 'info', rule: 'ROLES_CAP_REACHED', item: 'accounts', detail: '' },
		{ severity: 'high', rule: 'ALL_ROLE_HOLDER', item: '_SYSTEM', detail: 'holds %All' },
		{ severity: 'medium', rule: 'UNAUTHENTICATED_SERVICE', item: '%Service_Open', detail: '' },
		{ severity: 'high', rule: 'AUDIT_DISABLED', item: 'audit', detail: '' }
	],
	details: { accounts: [] }
};

describe('isReport', () => {
	it('recognises a spec 013 report by its summary and findings', () => {
		expect(isReport(report)).toBe(true);
	});

	it('does not take other results for reports', () => {
		expect(isReport({ databases: [] })).toBe(false);
		expect(isReport(null)).toBe(false);
		expect(isReport([report])).toBe(false);
	});
});

describe('orderedFindings', () => {
	it('lists high, then medium, then info, keeping the order within a severity', () => {
		expect(orderedFindings(report).map((f) => f.rule)).toEqual(['ALL_ROLE_HOLDER', 'AUDIT_DISABLED', 'UNAUTHENTICATED_SERVICE', 'ROLES_CAP_REACHED']);
	});
});

describe('labels', () => {
	it('severity as text, and the counts line', () => {
		expect(severityLabel('high')).toBe('HIGH');
		expect(severityLabel('medium')).toBe('MEDIUM');
		expect(severityLabel('info')).toBe('INFO');
		expect(summaryLine(report)).toBe('2 high · 1 medium · 1 info');
	});
});

describe('hasResult', () => {
	it('only for a finished step that stored something', () => {
		expect(hasResult('completed', { databases: [] })).toBe(true);
		expect(hasResult('failed', report)).toBe(true);
		expect(hasResult('running', report)).toBe(false);
		expect(hasResult('completed', null)).toBe(false);
	});
});
