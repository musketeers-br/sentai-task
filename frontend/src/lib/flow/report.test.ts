import { describe, expect, it } from 'vitest';
import { findingsForStep, formatErrors, formatWarnings, type ValidationReport } from './report';

// Codes and messages as sentai.validation.FlowValidator emits them.
const report: ValidationReport = {
	errors: [
		{ stepId: '04', code: 'PARAMETER_SCHEMA', message: 'purge-audit-records requires parameters.daysToKeep' },
		{ stepId: '02', code: 'NAMESPACE_NOT_FOUND', message: "Namespace 'DOCBOOK' does not exist on this instance" },
		{ stepId: '', code: 'CYCLE_DETECTED', message: "The flow's edge graph contains a cycle" }
	],
	warnings: [
		{
			stepId: '03',
			code: 'PRECONDITION_READ_ONLY',
			message: 'Database mounted read-only. This step type requires write access to the directory.'
		}
	]
};

describe('formatWarnings (FR-009)', () => {
	it('matches the UI-001 status-bar wording', () => {
		expect(formatWarnings(report)).toBe('1 precondition not met (#03)');
	});

	it('lists every affected step, in id order', () => {
		const two = { errors: [], warnings: [report.warnings[0], { ...report.warnings[0], stepId: '01' }] };
		expect(formatWarnings(two)).toBe('2 precondition not met (#01, #03)');
	});

	it('is null when there is nothing to report', () => {
		expect(formatWarnings({ errors: [], warnings: [] })).toBeNull();
	});
});

describe('formatErrors', () => {
	it('counts errors and names each affected step, flow-level errors as "flow"', () => {
		expect(formatErrors(report)).toBe('3 errors block scheduling (#02, #04, flow)');
	});

	it('uses the singular for one error', () => {
		expect(formatErrors({ errors: [report.errors[0]], warnings: [] })).toBe(
			'1 error blocks scheduling (#04)'
		);
	});
});

describe('findingsForStep', () => {
	it('returns that step’s findings with messages untouched (Constitution IV)', () => {
		expect(findingsForStep(report, '04').errors.map((f) => f.message)).toEqual([
			'purge-audit-records requires parameters.daysToKeep'
		]);
		expect(findingsForStep(report, '03').warnings).toHaveLength(1);
		expect(findingsForStep(null, '03')).toEqual({ errors: [], warnings: [] });
	});
});
