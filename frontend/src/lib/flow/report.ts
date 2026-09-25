// ValidationReport as FlowValidator returns it. Errors block scheduling; warnings never do
// (FR-010). Messages are displayed exactly as the platform wrote them (Constitution IV).

export interface Finding {
	stepId: string | null;
	code: string;
	message: string;
}

export interface ValidationReport {
	errors: Finding[];
	warnings: Finding[];
}

export interface StepFindings {
	errors: Finding[];
	warnings: Finding[];
}

function refs(findings: Finding[]): string {
	const steps = [...new Set(findings.filter((f) => f.stepId).map((f) => `#${f.stepId}`))].sort();
	const flowLevel = findings.some((f) => !f.stepId) ? ['flow'] : [];
	return [...steps, ...flowLevel].join(', ');
}

export function formatWarnings(report: ValidationReport | null): string | null {
	if (!report?.warnings.length) return null;
	return `${report.warnings.length} precondition not met (${refs(report.warnings)})`;
}

export function formatErrors(report: ValidationReport | null): string | null {
	if (!report?.errors.length) return null;
	const n = report.errors.length;
	return `${n} ${n === 1 ? 'error blocks' : 'errors block'} scheduling (${refs(report.errors)})`;
}

export function findingsForStep(report: ValidationReport | null, stepId: string): StepFindings {
	if (!report) return { errors: [], warnings: [] };
	return {
		errors: report.errors.filter((f) => f.stepId === stepId),
		warnings: report.warnings.filter((f) => f.stepId === stepId)
	};
}
