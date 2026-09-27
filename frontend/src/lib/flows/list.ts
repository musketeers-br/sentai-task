// Spec 010 US1/US2: the flow list as *Open flow…* shows it, and the default name of a new flow.
// Pure — no Svelte, no I/O. The platform decides every clash; these helpers only avoid one.

/** One row of GET /flows (data-model §1); `savedAt` in the platform's `YYYY-MM-DD HH:MM:SS`. */
export interface FlowSummaryView {
	id: string;
	name: string;
	revision: number;
	savedAt: string | null;
}

const pad = (n: number) => String(n).padStart(2, '0');

/**
 * `Untitled flow YYYY-MM-DD HH:MM:SS` in local time, with ` (2)`, ` (3)`… while the name clashes
 * (case-insensitively, like the platform's unique name index) with one of `takenNames`.
 */
export function defaultFlowName(now: Date, takenNames: readonly string[]): string {
	const stamp =
		`${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ` +
		`${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
	const base = `Untitled flow ${stamp}`;
	const taken = new Set(takenNames.map((n) => n.toLowerCase()));
	let name = base;
	for (let n = 2; taken.has(name.toLowerCase()); n++) name = `${base} (${n})`;
	return name;
}

/**
 * FR-002: most recently saved first. The platform's `YYYY-MM-DD HH:MM:SS` sorts chronologically
 * as text; a flow without `savedAt` goes last; ties break on name. Returns a new array.
 */
export function orderBySaved(list: readonly FlowSummaryView[]): FlowSummaryView[] {
	return [...list].sort((a, b) => {
		if (a.savedAt !== b.savedAt) {
			if (a.savedAt === null) return 1;
			if (b.savedAt === null) return -1;
			return a.savedAt < b.savedAt ? 1 : -1;
		}
		return a.name.localeCompare(b.name);
	});
}

/** FR-002: names containing `text` (trimmed), ignoring case; an empty filter keeps everything. */
export function filterByName(list: readonly FlowSummaryView[], text: string): FlowSummaryView[] {
	const needle = text.trim().toLowerCase();
	return needle === '' ? [...list] : list.filter((f) => f.name.toLowerCase().includes(needle));
}
