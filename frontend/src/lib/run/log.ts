// Spec 012 US1 (plan D-9): the run log as the panel shows it. The API returns it newest first
// (spec 003 FR-025), ties already in write order; the panel reads oldest first.
import type { LogEntry } from './run';

export const EMPTY_LOG_TEXT = 'No log was recorded for runs before this version.';

export function chronological(log: readonly LogEntry[]): LogEntry[] {
	return [...log].reverse();
}

export function severityLabel(severity: string): 'INFO' | 'WARN' | 'ERROR' {
	if (severity === 'error') return 'ERROR';
	if (severity === 'warning') return 'WARN';
	return 'INFO';
}
