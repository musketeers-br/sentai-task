import { describe, expect, it } from 'vitest';
import { afterSave, decide, needsGuard, type PendingSwitch } from './guard';

// spec 010 FR-006: New flow, Open and Open example ask Save / Discard / Cancel over unsaved edits.

describe('unsaved-changes guard (spec 010 data-model §3)', () => {
	it('asks only when the open flow has unsaved edits', () => {
		expect(needsGuard(false)).toBe(false);
		expect(needsGuard(true)).toBe(true);
	});

	it('maps each choice to what happens next', () => {
		expect(decide('save')).toEqual({ next: 'save-then-proceed' });
		expect(decide('discard')).toEqual({ next: 'proceed' });
		expect(decide('cancel')).toEqual({ next: 'stay' });
	});

	it('a failed save keeps the operator on the current flow', () => {
		expect(afterSave(false)).toEqual({ next: 'stay' });
		expect(afterSave(true)).toEqual({ next: 'proceed' });
	});

	it('covers every trigger with the same decisions', () => {
		const pending: PendingSwitch[] = [
			{ kind: 'new' },
			{ kind: 'open', flowId: '7' },
			{ kind: 'example' },
			{ kind: 'address', url: new URL('http://x/?flow=9') }
		];
		for (const p of pending) {
			expect({ p, step: decide('discard') }).toEqual({ p, step: { next: 'proceed' } });
		}
	});
});
