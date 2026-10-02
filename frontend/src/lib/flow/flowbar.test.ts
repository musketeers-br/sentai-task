import { describe, expect, it } from 'vitest';
import { flowBarState, type FlowBarInput } from './flowbar';

/**
 * Spec 023 T006 (data-model §2, FR-005, FR-006). Written before `flowbar.ts` existed
 * (Principle V): the flow bar's save state and the reason a disabled action shows as text.
 */

const SAVED: FlowBarInput = {
	steps: 2,
	id: '7',
	revision: 3,
	savedAt: '2026-10-01 20:14:09',
	dirty: false,
	validating: false,
	scheduleBlocked: false
};

describe('flowBarState — save state', () => {
	it('is "unsaved" while the flow has no id', () => {
		expect(flowBarState({ ...SAVED, id: null }).saveState).toEqual({ kind: 'unsaved' });
	});

	it('gives the revision and the platform time as HH:MM', () => {
		expect(flowBarState(SAVED).saveState).toEqual({ kind: 'saved', revision: 3, savedAt: '20:14', edited: false });
	});

	it('marks a saved flow with unsaved edits as edited', () => {
		expect(flowBarState({ ...SAVED, dirty: true }).saveState).toMatchObject({ kind: 'saved', edited: true });
	});

	it('formats the meta line the bar shows', () => {
		expect(flowBarState({ ...SAVED, id: null }).meta).toBe('unsaved');
		expect(flowBarState(SAVED).meta).toBe('rev 3 · saved 20:14');
		expect(flowBarState({ ...SAVED, dirty: true }).meta).toBe('rev 3 · saved 20:14 · edited');
	});
});

describe('flowBarState — actions and their reason', () => {
	it('enables every action on a valid flow with steps, with no reason', () => {
		const s = flowBarState(SAVED);
		expect(s.actions).toEqual({
			validate: { enabled: true },
			run: { enabled: true },
			schedule: { enabled: true }
		});
		expect(s.reason).toBeNull();
	});

	it('disables validate, run and schedule on an empty flow and says why', () => {
		const s = flowBarState({ ...SAVED, steps: 0 });
		expect(s.actions.validate.enabled).toBe(false);
		expect(s.actions.run.enabled).toBe(false);
		expect(s.actions.schedule.enabled).toBe(false);
		expect(s.reason).toBe('add a step to enable running');
	});

	it('blocks run and schedule after a failed validation, keeps validate, and says why', () => {
		const s = flowBarState({ ...SAVED, scheduleBlocked: true });
		expect(s.actions.validate.enabled).toBe(true);
		expect(s.actions.run.enabled).toBe(false);
		expect(s.actions.schedule.enabled).toBe(false);
		expect(s.reason).toBe('fix the validation errors in the status bar');
	});

	it('disables validate while validating, without a reason (the button says Validating…)', () => {
		const s = flowBarState({ ...SAVED, validating: true });
		expect(s.actions.validate.enabled).toBe(false);
		expect(s.actions.run.enabled).toBe(true);
		expect(s.reason).toBeNull();
	});

	it('prefers the empty-flow reason when both apply', () => {
		expect(flowBarState({ ...SAVED, steps: 0, scheduleBlocked: true }).reason).toBe('add a step to enable running');
	});
});
