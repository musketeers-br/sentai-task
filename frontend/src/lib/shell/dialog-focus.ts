// Spec 021 (plan D-6 / research R-9): the one owner of the "Tab wraps inside an open dialog"
// rule, extracted from Modal.svelte so the tour's overlay (FR-006) obeys the same focus
// contract without a second copy. Behaviour is byte-for-byte what Modal.svelte had.

const FOCUSABLE =
	'button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), a[href], [tabindex]:not([tabindex="-1"])';

/** Tab wraps inside the dialog instead of leaving the page for the browser's chrome. */
export function wrapTab(dialog: HTMLDialogElement, event: KeyboardEvent): void {
	if (event.key !== 'Tab') return;
	const items = [...dialog.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null);
	if (items.length === 0) return;
	const first = items[0];
	const last = items[items.length - 1];
	const inside = dialog.contains(document.activeElement);
	if (event.shiftKey && (document.activeElement === first || !inside)) {
		event.preventDefault();
		last.focus();
	} else if (!event.shiftKey && (document.activeElement === last || !inside)) {
		event.preventDefault();
		first.focus();
	}
}
