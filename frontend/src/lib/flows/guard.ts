// Spec 010 FR-006, spec 022 D-7: the one unsaved-changes guard. New flow, Open flow…, Use (a
// runbook — the example included, as a card) and any navigation that changes the open flow ask
// Save / Discard / Cancel over unsaved edits. Pure — the dialog (UnsavedChangesDialog.svelte)
// and the page's `guarded()` act on these values.

import type { Runbook } from './runbooks';

export type PendingSwitch =
	| { kind: 'new' }
	| { kind: 'open'; flowId: string }
	| { kind: 'runbook'; runbook: Runbook }
	/** Back/forward or a link that changes the `flow` in the address. */
	| { kind: 'address'; url: URL };

export type GuardChoice = 'save' | 'discard' | 'cancel';
export type GuardStep = { next: 'proceed' } | { next: 'stay' } | { next: 'save-then-proceed' };

export function needsGuard(dirty: boolean): boolean {
	return dirty;
}

export function decide(choice: GuardChoice): GuardStep {
	switch (choice) {
		case 'save':
			return { next: 'save-then-proceed' };
		case 'discard':
			return { next: 'proceed' };
		case 'cancel':
			return { next: 'stay' };
	}
}

/** The second half of `save-then-proceed`: a refused save keeps the operator where they are. */
export function afterSave(ok: boolean): GuardStep {
	return ok ? { next: 'proceed' } : { next: 'stay' };
}
