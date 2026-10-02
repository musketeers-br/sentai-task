// Spec 023 (data-model §2, FR-005, FR-006): the flow bar's view model. Pure — plain values in, no
// Svelte — so the rule for "why is Run now disabled" is a case in `flowbar.test.ts`, and the bar
// shows that reason as text instead of hiding it in a tooltip.

export interface FlowBarInput {
	steps: number;
	id: string | null;
	revision: number;
	/** As the platform reports it: "YYYY-MM-DD HH:MM:SS". */
	savedAt: string | null;
	dirty: boolean;
	validating: boolean;
	scheduleBlocked: boolean;
}

export type SaveState = { kind: 'unsaved' } | { kind: 'saved'; revision: number; savedAt: string | null; edited: boolean };

export interface FlowBarState {
	saveState: SaveState;
	/** The line under the name: "unsaved" or "rev N · saved HH:MM[ · edited]". */
	meta: string;
	actions: Record<'validate' | 'run' | 'schedule', { enabled: boolean }>;
	/** One reason for the disabled actions, shown beside them; null when none needs explaining. */
	reason: string | null;
}

export const REASON_EMPTY = 'add a step to enable running';
export const REASON_INVALID = 'fix the validation errors in the status bar';

export function flowBarState(input: FlowBarInput): FlowBarState {
	const saveState: SaveState =
		input.id === null
			? { kind: 'unsaved' }
			: { kind: 'saved', revision: input.revision, savedAt: input.savedAt ? input.savedAt.slice(11, 16) : null, edited: input.dirty };

	const empty = input.steps === 0;
	const actions = {
		validate: { enabled: !empty && !input.validating },
		run: { enabled: !empty && !input.scheduleBlocked },
		schedule: { enabled: !empty && !input.scheduleBlocked }
	};
	const reason = empty ? REASON_EMPTY : input.scheduleBlocked ? REASON_INVALID : null;

	return { saveState, meta: metaLine(saveState), actions, reason };
}

function metaLine(state: SaveState): string {
	if (state.kind === 'unsaved') return 'unsaved';
	return `rev ${state.revision} · saved ${state.savedAt ?? '—'}${state.edited ? ' · edited' : ''}`;
}
