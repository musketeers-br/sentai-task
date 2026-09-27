// Spec 010 US5 (data-model §6): the getting-started guide's state. What is remembered per browser
// is only the "don't show again" choice; "already shown in this visit" lives in memory and ends at
// sign-out. A visit starts with a sign-in typed with the password — a reload that keeps the
// sign-in is the same visit (spec Clarifications).
import type { SessionOrigin } from '$lib/api/session.svelte';
import { isDismissed, setDismissed, type PreferenceStorage } from './preference';
import { GUIDE_STEPS } from './steps';

export function shouldAutoOpen(visit: { origin: SessionOrigin | null; dismissed: boolean; shownThisVisit: boolean }): boolean {
	return visit.origin === 'password' && !visit.dismissed && !visit.shownThisVisit;
}

function browserStorage(): PreferenceStorage | null {
	try {
		return typeof localStorage === 'undefined' ? null : localStorage;
	} catch {
		return null;
	}
}

export class Guide {
	open = $state(false);
	step = $state(1);
	dontShow = $state(false);
	/** Memory only: set when the guide opened by itself; reset at sign-out. */
	shownThisVisit = false;

	readonly steps = GUIDE_STEPS;
	#storage: () => PreferenceStorage | null;

	constructor(storage: () => PreferenceStorage | null = browserStorage) {
		this.#storage = storage;
	}

	dismissed(): boolean {
		return isDismissed(this.#storage());
	}

	autoOpen(): void {
		this.shownThisVisit = true;
		this.#show();
	}

	/** FR-023: at step 1, whatever was shown or chosen before. */
	openFromHelp(): void {
		this.#show();
	}

	next(): void {
		this.step = Math.min(this.step + 1, this.steps.length);
	}

	back(): void {
		this.step = Math.max(this.step - 1, 1);
	}

	/** FR-022: the box as it is when the guide closes decides later sign-ins. */
	close(): void {
		// Only a guide that is open has a choice to keep: the Close button and the dialog's own
		// close (Escape) may both end here, and sign-out calls it whether or not it is open.
		if (!this.open) return;
		this.open = false;
		setDismissed(this.#storage(), this.dontShow);
	}

	resetVisit(): void {
		this.shownThisVisit = false;
	}

	#show(): void {
		this.step = 1;
		this.dontShow = this.dismissed();
		this.open = true;
	}
}

export const guide = new Guide();
