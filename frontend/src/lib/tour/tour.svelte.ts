// Spec 021 (data-model §2): the tour's whole state. No storage and no first-use detection —
// the button is the only entry (FR-009) and every launch behaves identically (FR-010).
import { TOUR_STEPS } from './steps';

export class Tour {
	open = $state(false);
	/** 1-based index into TOUR_STEPS. */
	step = $state(1);
	readonly steps = TOUR_STEPS;

	/** FR-001: the Tour button's one effect — always from mark 1. */
	start(): void {
		this.step = 1;
		this.open = true;
	}

	/** FR-005: advances one mark, clamps at the last, never opens. */
	next(): void {
		if (!this.open) return;
		this.step = Math.min(this.step + 1, this.steps.length);
	}

	/** FR-005: ends the tour from any mark (Escape routes here too, FR-006). */
	skip(): void {
		this.open = false;
	}

	/** FR-005: the finishing control on the last mark. */
	finish(): void {
		this.open = false;
	}

	/** FR-011: the page's close rule; safe to call when already closed (idempotent). */
	close(): void {
		this.open = false;
	}
}

export const tour = new Tour();
