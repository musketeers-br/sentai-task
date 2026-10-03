// Spec 021 FR-002/FR-003 (data-model §1, contracts/tour.md §3): the three fixed coach marks.
// Exactly these exist, declared here in the codebase; nothing comes from input (Constitution II).

export type TourMarkKey = 'palette' | 'connections' | 'validate-run';

export interface TourMark {
	readonly key: TourMarkKey;
	/** Anchor selectors in contract order; resolved by the component, the only DOM edge. */
	readonly anchor: readonly string[];
	/** The English message the mark conveys (FR-013). */
	readonly body: string;
}

export const TOUR_STEPS: readonly TourMark[] = [
	{
		key: 'palette',
		anchor: ['aside[aria-label="Step types"]'],
		body: 'This is the palette — drag a step onto the canvas.'
	},
	{
		key: 'connections',
		anchor: ['.canvas[role="application"]'],
		body: 'Connect two steps to create a dependency.'
	},
	{
		key: 'validate-run',
		anchor: ['[data-tour-target="validate"]', '[data-tour-target="run"]'],
		body: 'Validate the flow, then run it.'
	}
];
