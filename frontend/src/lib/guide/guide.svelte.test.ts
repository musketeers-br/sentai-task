import { describe, expect, it } from 'vitest';
import { Guide, shouldAutoOpen } from './guide.svelte';
import { GUIDE_KEY, type PreferenceStorage } from './preference';
import { GUIDE_STEPS } from './steps';

// spec 010 US5 (data-model §6): when the guide opens by itself, Help, paging, closing.

function fake(initial: Record<string, string> = {}) {
	const data = new Map(Object.entries(initial));
	const storage: PreferenceStorage = {
		getItem: (k) => data.get(k) ?? null,
		setItem: (k, v) => void data.set(k, v),
		removeItem: (k) => void data.delete(k)
	};
	return { data, storage };
}

describe('shouldAutoOpen (FR-020)', () => {
	it('opens only after a password sign-in, when not dismissed and not yet shown in this visit', () => {
		for (const origin of ['password', 'restored', null] as const) {
			for (const dismissed of [false, true]) {
				for (const shownThisVisit of [false, true]) {
					expect(shouldAutoOpen({ origin, dismissed, shownThisVisit }), `${origin}/${dismissed}/${shownThisVisit}`).toBe(
						origin === 'password' && !dismissed && !shownThisVisit
					);
				}
			}
		}
	});
});

describe('Guide', () => {
	it('has the six steps of Story 5, in order', () => {
		expect(GUIDE_STEPS.map((s) => s.title)).toEqual([
			'Welcome',
			'Open the example',
			'Build a flow',
			'Validate and run',
			'Save, Save as, Open',
			'Schedule and explore'
		]);
		expect(GUIDE_STEPS[1].action).toBe('open-example');
	});

	it('autoOpen starts at step 1 and remembers it was shown in this visit (memory only)', () => {
		const { data, storage } = fake();
		const guide = new Guide(() => storage);
		guide.autoOpen();
		expect(guide.open).toBe(true);
		expect(guide.step).toBe(1);
		expect(guide.dontShow).toBe(false);
		expect(guide.shownThisVisit).toBe(true);
		expect(data.size).toBe(0);
	});

	it('Help opens at step 1 with the box as stored, whatever was shown this visit (FR-023)', () => {
		const { storage } = fake({ [GUIDE_KEY]: '1' });
		const guide = new Guide(() => storage);
		guide.autoOpen();
		guide.next();
		guide.close();
		guide.openFromHelp();
		expect(guide.open).toBe(true);
		expect(guide.step).toBe(1);
		expect(guide.dontShow).toBe(true);
	});

	it('paging stays within 1…6', () => {
		const guide = new Guide(() => null);
		guide.openFromHelp();
		guide.back();
		expect(guide.step).toBe(1);
		for (let i = 0; i < 10; i++) guide.next();
		expect(guide.step).toBe(6);
	});

	it('closing stores the box as it is at that moment (FR-022)', () => {
		const { data, storage } = fake();
		const guide = new Guide(() => storage);
		guide.autoOpen();
		guide.dontShow = true;
		guide.close();
		expect(guide.open).toBe(false);
		expect(data.get(GUIDE_KEY)).toBe('1');
		guide.openFromHelp();
		guide.dontShow = false;
		guide.close();
		expect(data.has(GUIDE_KEY)).toBe(false);
	});

	it('closing a guide that is not open keeps the stored choice (sign-out after a reload)', () => {
		const { data, storage } = fake({ [GUIDE_KEY]: '1' });
		const guide = new Guide(() => storage);
		guide.close();
		expect(data.get(GUIDE_KEY)).toBe('1');
	});

	it('sign-out ends the visit', () => {
		const guide = new Guide(() => null);
		guide.autoOpen();
		guide.resetVisit();
		expect(guide.shownThisVisit).toBe(false);
	});
});
