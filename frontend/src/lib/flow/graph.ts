export interface EdgeRef {
	source: string;
	target: string;
}

export type ConnectionCheck = { ok: true } | { ok: false; reason: 'self' | 'duplicate' | 'cycle' };

/** Adding source→target closes a cycle iff target can already reach source. */
export function wouldCreateCycle(edges: EdgeRef[], source: string, target: string): boolean {
	if (source === target) return true;
	const outgoing = new Map<string, string[]>();
	for (const e of edges) {
		const list = outgoing.get(e.source) ?? [];
		list.push(e.target);
		outgoing.set(e.source, list);
	}
	const seen = new Set<string>();
	const stack = [target];
	while (stack.length) {
		const current = stack.pop()!;
		if (current === source) return true;
		if (seen.has(current)) continue;
		seen.add(current);
		stack.push(...(outgoing.get(current) ?? []));
	}
	return false;
}

export function checkConnection(edges: EdgeRef[], source: string, target: string): ConnectionCheck {
	if (source === target) return { ok: false, reason: 'self' };
	if (edges.some((e) => e.source === source && e.target === target)) {
		return { ok: false, reason: 'duplicate' };
	}
	if (wouldCreateCycle(edges, source, target)) return { ok: false, reason: 'cycle' };
	return { ok: true };
}

export function incomingSources(edges: EdgeRef[], target: string): string[] {
	return edges
		.filter((e) => e.target === target)
		.map((e) => e.source)
		.sort();
}

export function joinTargets(edges: EdgeRef[]): string[] {
	const counts = new Map<string, number>();
	for (const e of edges) counts.set(e.target, (counts.get(e.target) ?? 0) + 1);
	return [...counts]
		.filter(([, n]) => n >= 2)
		.map(([target]) => target)
		.sort();
}
