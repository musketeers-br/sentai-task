// Spec 010 FR-022/FR-024: "Don't show this again", remembered per browser. A display preference,
// not a permission (Clarifications). Same pattern as lib/shell/theme.svelte.ts: every access is
// caught, so a browser that refuses storage just shows the guide again — never an error.

export const GUIDE_KEY = 'sentai.guide.dismissed';

export type PreferenceStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

export function isDismissed(storage: PreferenceStorage | null): boolean {
	try {
		return storage?.getItem(GUIDE_KEY) === '1';
	} catch {
		return false;
	}
}

/** Ticked stores "1"; unticked removes the key. */
export function setDismissed(storage: PreferenceStorage | null, dismissed: boolean): void {
	try {
		if (dismissed) storage?.setItem(GUIDE_KEY, '1');
		else storage?.removeItem(GUIDE_KEY);
	} catch {
		// Not remembered: the guide opens again on the next sign-in (FR-024).
	}
}
