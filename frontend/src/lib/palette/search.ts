import { paletteGroups, typeLabel, type StepCategory, type StepTypeInfo } from '$lib/flow/document';

/**
 * Spec 011: the palette's search view model. Pure — no `fetch`, no DOM, no state — so every rule in
 * contracts/palette-search.md is a case in `search.test.ts` and the component is left holding only
 * the input, a debounce timer and the latest outcome.
 */

export type UnavailableReason =
	| 'not-configured'
	| 'unreachable'
	| 'slow'
	| 'incompatible'
	| 'warming'
	| 'error';

export type StepSearchOutcome =
	| { available: true; matches: { type: string; score: number }[] }
	| { available: false; reason: UnavailableReason };

/** A palette section widens a category group with the one group the ranking adds. */
export type PaletteSection = { id: StepCategory | 'suggested'; types: StepTypeInfo[] };

/**
 * Today's substring rule, extracted from `Palette.svelte` as it stood (FR-003).
 *
 * The `className` match is **kept**, not deleted: it is a local match on data the browser already
 * has, so it is not in tension with the closed capability set. The semantic path never reads a
 * class name (R-009); this one does, and always did.
 */
export function filterLocally(registry: StepTypeInfo[], q: string): StepTypeInfo[] {
	const needle = q.trim().toLowerCase();
	if (!needle) return registry;
	return registry.filter(
		(t) =>
			t.type.includes(needle) ||
			typeLabel(t).toLowerCase().includes(needle) ||
			t.className.toLowerCase().includes(needle)
	);
}

/**
 * Ranked identifiers → catalog entries, best first. An identifier the registry does not hold is
 * dropped, and a repeated identifier is kept only in its first position, so this can only ever
 * reorder or drop what it was handed and never create or duplicate an entry (R-011, FR-013).
 *
 * The API's order is kept, including among equal scores: this never re-sorts and never re-applies
 * the floor, because a match arriving here is already above it. The duplicate guard does not depend
 * on the corpus holding one row per type — it is the view model refusing to render an entry twice.
 */
export function suggestionsFor(registry: StepTypeInfo[], outcome: StepSearchOutcome): StepTypeInfo[] {
	if (!outcome.available) return [];
	const byType = new Map(registry.map((t) => [t.type, t]));
	const seen = new Set<string>();
	return outcome.matches
		.map((m) => byType.get(m.type))
		.filter((t): t is StepTypeInfo => {
			if (t === undefined || seen.has(t.type)) return false;
			seen.add(t.type);
			return true;
		});
}

/**
 * Today's grouped palette, with a leading `suggested` group when the ranking offers something, and
 * no entry listed twice.
 *
 * `unavailable` and an empty ranking are deliberately indistinguishable here: both render today's
 * local groups, and the reason is not carried any further than this signature (R-007, FR-023).
 */
export function paletteSections(
	registry: StepTypeInfo[],
	q: string,
	outcome: StepSearchOutcome | null
): PaletteSection[] {
	const local = filterLocally(registry, q);
	const suggested = outcome ? suggestionsFor(registry, outcome) : [];
	if (suggested.length === 0) {
		return paletteGroups(local).map((g) => ({ id: g.id, types: g.types }));
	}

	const suggestedTypes = new Set(suggested.map((t) => t.type));
	// The remainder drops a suggested entry, so it is not offered twice: the suggestion group leads
	// with it and its own category group no longer repeats it.
	const rest = local.filter((t) => !suggestedTypes.has(t.type));
	return [
		{ id: 'suggested', types: suggested },
		...paletteGroups(rest).map((g) => ({ id: g.id, types: g.types }))
	];
}
