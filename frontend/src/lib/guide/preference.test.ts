import { describe, expect, it } from 'vitest';
import { GUIDE_KEY, isDismissed, setDismissed, type PreferenceStorage } from './preference';

// spec 010 FR-022, FR-024: "Don't show this again", per browser; a storage that refuses is no error.

function fake(initial: Record<string, string> = {}) {
	const data = new Map(Object.entries(initial));
	const storage: PreferenceStorage = {
		getItem: (k) => data.get(k) ?? null,
		setItem: (k, v) => void data.set(k, v),
		removeItem: (k) => void data.delete(k)
	};
	return { data, storage };
}

const boom = () => {
	throw new Error('SecurityError');
};

describe('guide preference', () => {
	it('is not dismissed until "1" is stored', () => {
		expect(isDismissed(fake().storage)).toBe(false);
		expect(isDismissed(fake({ [GUIDE_KEY]: '0' }).storage)).toBe(false);
		expect(isDismissed(fake({ [GUIDE_KEY]: '1' }).storage)).toBe(true);
		expect(isDismissed(null)).toBe(false);
	});

	it('ticking stores "1"; unticking removes the key', () => {
		const { data, storage } = fake();
		setDismissed(storage, true);
		expect(data.get(GUIDE_KEY)).toBe('1');
		setDismissed(storage, false);
		expect(data.has(GUIDE_KEY)).toBe(false);
	});

	it('a storage that throws reads as not dismissed and never raises (FR-024)', () => {
		const refusing: PreferenceStorage = { getItem: boom, setItem: boom, removeItem: boom };
		expect(isDismissed(refusing)).toBe(false);
		expect(() => setDismissed(refusing, true)).not.toThrow();
		expect(() => setDismissed(refusing, false)).not.toThrow();
	});
});
