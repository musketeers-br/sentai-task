// Spec 021 (data-model §3): pure spotlight/card geometry. Rect/Point/Size are plain objects;
// the component converts getBoundingClientRect() at the DOM edge (Principle I).

export interface Rect {
	x: number;
	y: number;
	width: number;
	height: number;
}

export interface Size {
	width: number;
	height: number;
}

export interface Point {
	x: number;
	y: number;
}

/** The bounding box of all anchor rects; null when a selector matched nothing (Constitution IV). */
export function unionRect(rects: readonly Rect[]): Rect | null {
	if (rects.length === 0) return null;
	let x0 = Infinity;
	let y0 = Infinity;
	let x1 = -Infinity;
	let y1 = -Infinity;
	for (const rect of rects) {
		x0 = Math.min(x0, rect.x);
		y0 = Math.min(y0, rect.y);
		x1 = Math.max(x1, rect.x + rect.width);
		y1 = Math.max(y1, rect.y + rect.height);
	}
	return { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
}

/** The spotlight hole: the anchor region grown by the inset on every side. */
export function pad(rect: Rect, inset: number): Rect {
	return {
		x: rect.x - inset,
		y: rect.y - inset,
		width: rect.width + 2 * inset,
		height: rect.height + 2 * inset
	};
}

const GAP = 12;

function clamp(value: number, low: number, high: number): number {
	return Math.min(Math.max(value, low), high);
}

/**
 * Where the message card goes: 12 px below the target when there is room, otherwise 12 px above
 * it, and always at least 12 px inside the viewport — so a target wider than the viewport, or a
 * viewport shorter than the card, still yields an on-screen card (spec edge case).
 */
export function placeCard(target: Rect, viewport: Size, card: Size): Point {
	const below = target.y + target.height + GAP;
	const y =
		below + card.height > viewport.height - GAP ? target.y - card.height - GAP : below;
	const x = clamp(target.x, GAP, Math.max(GAP, viewport.width - card.width - GAP));
	return { x, y: clamp(y, GAP, Math.max(GAP, viewport.height - card.height - GAP)) };
}
