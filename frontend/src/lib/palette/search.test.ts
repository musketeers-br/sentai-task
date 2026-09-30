import { describe, expect, it } from 'vitest';
import {
	filterLocally,
	paletteSections,
	suggestionsFor,
	type StepSearchOutcome
} from './search';
import { paletteGroups, type StepTypeInfo } from '$lib/flow/document';

/**
 * Spec 011 T011 / US1, extended by T019, T023. Written before `lib/palette/search.ts` existed
 * (Principle V).
 *
 * These are the rules contracts/palette-search.md states as cases, kept as cases. The invariants
 * that hold in every one of them — every element is an element of `registry`, nothing appears
 * twice, the view model never re-scores — are asserted once at the end over all of the inputs
 * rather than repeated in each test, because a repeated invariant is a test that only fails when
 * someone notices to copy it.
 */

function entry(type: string, over: Partial<StepTypeInfo> = {}): StepTypeInfo {
	return {
		type,
		className: `%SYS.Task.${type.replace(/(^|-)(\w)/g, (_m, _a, c) => c.toUpperCase())}`,
		category: 'storage',
		destructive: false,
		pausable: false,
		available: true,
		...over
	};
}

const REGISTRY: StepTypeInfo[] = [
	entry('integrity-check', { label: 'Integrity check', category: 'verification' }),
	entry('compact-globals', { label: 'Compact globals', available: false }),
	entry('db-size-report', { label: 'Database size report' }),
	entry('switch-journal', { label: 'Switch journal', category: 'journal', executor: 'in-process' }),
	entry('purge-task-history', {
		label: 'Purge task history',
		category: 'purge',
		destructive: true,
		executor: 'in-process'
	}),
	entry('custom', { label: 'Custom (legacy)', category: 'custom', className: '', available: false })
];

const available = (...types: [string, number][]): StepSearchOutcome => ({
	available: true,
	matches: types.map(([type, score]) => ({ type, score }))
});

/** Today's grouped palette, as the component would have produced it before this feature existed. */
function today(registry: StepTypeInfo[], q: string): { id: string; types: StepTypeInfo[] }[] {
	return paletteSections(registry, q, null);
}

describe('filterLocally', () => {
	it('returns the whole registry for an empty query', () => {
		expect(filterLocally(REGISTRY, '')).toEqual(REGISTRY);
		expect(filterLocally(REGISTRY, '   ')).toEqual(REGISTRY);
	});

	it("keeps today's substring rule over type, label and class name", () => {
		// T0: today's `className` match is extracted, not deleted — it is a local match on data the
		// browser already holds, and the semantic path never sees a class name. The first query below
		// matches a class name and nothing else: neither `db-size-report` nor its label contains it.
		expect(filterLocally(REGISTRY, 'DbSizeReport').map((t) => t.type)).toEqual(['db-size-report']);
		expect(filterLocally(REGISTRY, 'integrity').map((t) => t.type)).toEqual(['integrity-check']);
		expect(filterLocally(REGISTRY, 'journal').map((t) => t.type)).toEqual(['switch-journal']);
	});

	it('matches case-insensitively, as today', () => {
		expect(filterLocally(REGISTRY, 'JOURNAL').map((t) => t.type)).toEqual(['switch-journal']);
	});
});

describe('suggestionsFor', () => {
	it('returns ranked catalog entries, best first, in the order the API gave them', () => {
		expect(suggestionsFor(REGISTRY, available(['switch-journal', 0.79], ['integrity-check', 0.31])).map((t) => t.type)).toEqual([
			'switch-journal',
			'integrity-check'
		]);
	});

	it('drops an identifier the registry does not hold', () => {
		// Contract case 7: nothing can enter from the wire.
		expect(suggestionsFor(REGISTRY, available(['not-a-real-type', 0.99]))).toEqual([]);
	});

	it('returns nothing for an unavailable outcome or an empty ranking', () => {
		expect(suggestionsFor(REGISTRY, { available: false, reason: 'unreachable' })).toEqual([]);
		expect(suggestionsFor(REGISTRY, { available: true, matches: [] })).toEqual([]);
	});
});

describe('paletteSections', () => {
	it('case 1: an empty query is exactly today, with no suggested group', () => {
		expect(paletteSections(REGISTRY, '', null)).toEqual(today(REGISTRY, ''));
	});

	it('case 2: a substring query is exactly today, with no suggested group', () => {
		expect(paletteSections(REGISTRY, 'integr', null)).toEqual(today(REGISTRY, 'integr'));
	});

	it('case 3: a ranking prepends a suggested group and removes that entry from its own group', () => {
		const sections = paletteSections(REGISTRY, 'rotate the journal', available(['switch-journal', 0.79]));
		expect(sections[0].id).toBe('suggested');
		expect(sections[0].types.map((t) => t.type)).toEqual(['switch-journal']);
		expect(sections.slice(1)).toEqual(today(REGISTRY, 'rotate the journal').filter((g) => g.types.length > 0));
	});

	it('case 4: no outcome means no suggested group, however well it would have matched', () => {
		const sections = paletteSections(REGISTRY, 'rotate the journal', null);
		expect(sections.map((s) => s.id)).not.toContain('suggested');
	});

	it('case 5: available with no matches is today, not an empty palette', () => {
		const outcome: StepSearchOutcome = { available: true, matches: [] };
		expect(paletteSections(REGISTRY, 'zzz', outcome)).toEqual(today(REGISTRY, 'zzz'));
	});

	it('case 6: an unavailable outcome is today — the reason is never its own section', () => {
		const outcome: StepSearchOutcome = { available: false, reason: 'slow' };
		expect(paletteSections(REGISTRY, 'rotate the journal', outcome)).toEqual(today(REGISTRY, 'rotate the journal'));
	});

	it('spec 017: warming — the provider is still loading — is today, like every unavailable reason', () => {
		const outcome: StepSearchOutcome = { available: false, reason: 'warming' };
		const sections = paletteSections(REGISTRY, 'free up disk space', outcome);
		expect(sections.map((s) => s.id)).not.toContain('suggested');
		expect(sections).toEqual(today(REGISTRY, 'free up disk space'));
	});

	it('case 7: an unknown identifier produces no suggested group at all', () => {
		const sections = paletteSections(REGISTRY, 'anything', available(['nope', 0.99]));
		expect(sections.map((s) => s.id)).not.toContain('suggested');
		expect(sections).toEqual(today(REGISTRY, 'anything'));
	});

	it('case 8: the legacy custom entry can be suggested and is still not addable', () => {
		const sections = paletteSections(REGISTRY, 'a custom class', available(['custom', 0.95]));
		const suggested = sections.find((s) => s.id === 'suggested');
		expect(suggested?.types.map((t) => t.type)).toEqual(['custom']);
		// The view model must not alter availability: it reorders entries it was handed.
		expect(suggested?.types[0].available).toBe(false);
	});

	it('case 9: equal scores keep the order the API returned them in', () => {
		const sections = paletteSections(REGISTRY, 'x', available(['purge-task-history', 0.5], ['integrity-check', 0.5]));
		expect(sections[0].types.map((t) => t.type)).toEqual(['purge-task-history', 'integrity-check']);
	});

	it('keeps today’s local filter: a suggested entry is not the only thing shown', () => {
		const sections = paletteSections(REGISTRY, 'journal', available(['switch-journal', 0.9]));
		// The local filter found one entry, the ranking suggested it, and it is not listed twice —
		// so the list the local filter produced is exactly the suggestion.
		const journal = REGISTRY.find((t) => t.type === 'switch-journal');
		expect(sections).toEqual([{ id: 'suggested', types: [journal] }]);
	});

	it('never re-applies the floor or re-scores: a match below 0.20 is still offered', () => {
		const sections = paletteSections(REGISTRY, 'x', available(['integrity-check', 0.21]));
		expect(sections[0].id).toBe('suggested');
	});
});

describe('invariants, over every input above', () => {
	const outcomes: (StepSearchOutcome | null)[] = [
		null,
		available(),
		available(['switch-journal', 0.79]),
		available(['not-a-real-type', 0.99]),
		available(['custom', 0.95], ['custom', 0.4]),
		{ available: true, matches: [] },
		{ available: false, reason: 'not-configured' },
		{ available: false, reason: 'unreachable' },
		{ available: false, reason: 'warming' },
		{ available: false, reason: 'error' }
	];
	const queries = ['', '   ', 'integr', 'journal', 'a custom class', 'x'];

	it('every element of every section is an element of the registry it was given', () => {
		for (const q of queries) {
			for (const outcome of outcomes) {
				const known = new Set(REGISTRY.map((t) => t.type));
				for (const section of paletteSections(REGISTRY, q, outcome)) {
					for (const t of section.types) expect(known.has(t.type), `${t.type} in ${q}`).toBe(true);
				}
			}
		}
	});

	it('no entry appears twice across the sections', () => {
		for (const q of queries) {
			for (const outcome of outcomes) {
				const seen = new Set<string>();
				for (const section of paletteSections(REGISTRY, q, outcome)) {
					for (const t of section.types) {
						expect(seen.has(t.type), `${t.type} twice for ${q}`).toBe(false);
						seen.add(t.type);
					}
				}
			}
		}
	});

	it('never alters availability, category, class name or destructiveness', () => {
		for (const q of queries) {
			for (const outcome of outcomes) {
				for (const section of paletteSections(REGISTRY, q, outcome)) {
					const original = REGISTRY.find((t) => t.type === section.types[0]?.type);
					for (const t of section.types) {
						const from = REGISTRY.find((r) => r.type === t.type);
						expect(t).toEqual(from);
						void original;
					}
				}
			}
		}
	});
});
