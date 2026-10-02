// Spec 023 (research R-4): what a destructive step type does, in words. Moved verbatim from
// `Inspector.svelte` so the inspector and the catalog detail say the same thing about the same type.

const NO_ROLLBACK = 'There is no rollback: it requires a valid backup taken today.';

export function consequence(type: string, parameters: Record<string, unknown>): string {
	if (type === 'purge-audit-records') {
		return `Permanently removes audit records older than ${parameters.daysToKeep ?? '?'} days. ${NO_ROLLBACK}`;
	}
	if (type === 'purge-task-history') return `Permanently removes task history records. ${NO_ROLLBACK}`;
	return `Permanently changes data on the instance. ${NO_ROLLBACK}`;
}
