import { describe, expect, it } from 'vitest';
import { consequence } from './consequence';

/**
 * Spec 023 T007 (research R-4): the warning text moved out of `Inspector.svelte` unchanged, so the
 * inspector and the catalog detail say the same thing about the same step type.
 */

const NO_ROLLBACK = 'There is no rollback: it requires a valid backup taken today.';

describe('consequence', () => {
	it('names the retention of purge-audit-records', () => {
		expect(consequence('purge-audit-records', { daysToKeep: 30 })).toBe(
			`Permanently removes audit records older than 30 days. ${NO_ROLLBACK}`
		);
	});

	it('says "?" when purge-audit-records has no retention yet', () => {
		expect(consequence('purge-audit-records', {})).toBe(`Permanently removes audit records older than ? days. ${NO_ROLLBACK}`);
	});

	it('describes purge-task-history', () => {
		expect(consequence('purge-task-history', {})).toBe(`Permanently removes task history records. ${NO_ROLLBACK}`);
	});

	it('falls back to the generic text for any other type', () => {
		expect(consequence('some-other-type', {})).toBe(`Permanently changes data on the instance. ${NO_ROLLBACK}`);
	});
});
