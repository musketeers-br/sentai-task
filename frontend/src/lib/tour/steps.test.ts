import { describe, expect, it } from 'vitest';
import { TOUR_STEPS } from './steps';

// spec 021 US1 (FR-002, FR-003, FR-013): the three fixed marks, their order, their anchors and
// their English copy — the contract the component renders and us30 asserts is the same data.

describe('TOUR_STEPS (contracts/tour.md §3)', () => {
	it('has exactly three marks in the order palette → connections → validate-run', () => {
		expect(TOUR_STEPS).toHaveLength(3);
		expect(TOUR_STEPS.map((s) => s.key)).toEqual(['palette', 'connections', 'validate-run']);
	});

	it('anchors are the contract registry selectors, in contract order', () => {
		expect(TOUR_STEPS[0].anchor).toEqual(['aside[aria-label="Step types"]']);
		expect(TOUR_STEPS[1].anchor).toEqual(['.canvas[role="application"]']);
		expect(TOUR_STEPS[2].anchor).toEqual(['[data-tour-target="validate"]', '[data-tour-target="run"]']);
	});

	it('every mark carries non-empty English text (FR-013)', () => {
		for (const step of TOUR_STEPS) {
			expect(step.body.trim().length, step.key).toBeGreaterThan(10);
			expect(step.body, step.key).toMatch(/^[A-Z]/);
			expect(step.body, step.key).toMatch(/[a-z] [a-z]/); // more than one word
		}
	});

	it('conveys the required content of each mark (FR-002)', () => {
		expect(TOUR_STEPS[0].body).toContain('palette');
		expect(TOUR_STEPS[0].body).toContain('drag');
		expect(TOUR_STEPS[1].body).toContain('Connect two steps');
		expect(TOUR_STEPS[2].body).toContain('Validate the flow');
		expect(TOUR_STEPS[2].body).toContain('run');
	});
});
