// Spec 013 FR-012: a step's stored result as the run view shows it. Reports (spec 013) carry a
// summary and findings, shown first; any other result (spec 005 reports, a platform job's own
// result) is shown as a tree. Values are the platform's or the product's, never rewritten.

export type Severity = 'high' | 'medium' | 'info';

export interface Finding {
	severity: Severity;
	rule: string;
	item: string;
	detail: string;
}

export interface Report {
	type: string;
	instance?: string;
	summary: { high: number; medium: number; info: number; itemsRead?: number; itemsOmitted?: number; findingsOmitted?: number };
	findings: Finding[];
	details: Record<string, unknown>;
	truncated?: boolean;
	omitted?: number;
}

const SEVERITY_ORDER: Severity[] = ['high', 'medium', 'info'];

export function isReport(result: unknown): result is Report {
	if (result === null || typeof result !== 'object' || Array.isArray(result)) return false;
	const r = result as Record<string, unknown>;
	return typeof r.summary === 'object' && r.summary !== null && Array.isArray(r.findings);
}

/** High first, then medium, then info; the report's own order within a severity. */
export function orderedFindings(report: Report): Finding[] {
	return SEVERITY_ORDER.flatMap((s) => report.findings.filter((f) => f.severity === s));
}

export function severityLabel(severity: string): string {
	return severity === 'high' ? 'HIGH' : severity === 'medium' ? 'MEDIUM' : 'INFO';
}

/** "2 high · 1 medium · 0 info", the counts line above the findings. */
export function summaryLine(report: Report): string {
	return SEVERITY_ORDER.map((s) => `${report.summary[s] ?? 0} ${s}`).join(' · ');
}

/** A step has something to show once it ended and stored a result. */
export function hasResult(state: string, result: unknown): boolean {
	return ['completed', 'failed', 'cancelled'].includes(state) && result !== null && result !== undefined;
}
