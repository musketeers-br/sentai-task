import { describe, expect, it } from 'vitest';
import { pad, placeCard, unionRect, type Rect } from './anchor';

// spec 021 US1 (data-model §3): the pure geometry of the spotlight and the card. The spec's
// edge case says the card never leaves the viewport, at any size the product supports.

const r = (x: number, y: number, width: number, height: number): Rect => ({ x, y, width, height });

describe('unionRect', () => {
	it('returns the rect itself for a single element', () => {
		expect(unionRect([r(10, 20, 30, 40)])).toEqual(r(10, 20, 30, 40));
	});

	it('returns the bounding box of several rects (mark 3 covers two buttons)', () => {
		expect(unionRect([r(10, 20, 30, 40), r(50, 5, 10, 60)])).toEqual(r(10, 5, 50, 60));
	});

	it('returns null for no rects — a missing anchor is a value, not a throw (Constitution IV)', () => {
		expect(unionRect([])).toBeNull();
	});
});

describe('pad (the spotlight hole)', () => {
	it('grows the rect by the inset on every side', () => {
		expect(pad(r(100, 100, 200, 40), 8)).toEqual(r(92, 92, 216, 56));
	});
});

describe('placeCard (the card never leaves the viewport)', () => {
	const viewport = { width: 1024, height: 640 };
	const card = { width: 320, height: 160 };

	it('prefers 12 px below the target when there is room', () => {
		expect(placeCard(r(100, 100, 200, 40), viewport, card)).toEqual({ x: 100, y: 152 });
	});

	it('flips above when the card would pass the viewport bottom', () => {
		// below would be y 612 + 160 > 640 - 12; above of target.y 560: 560 - 160 - 12 = 388
		expect(placeCard(r(100, 560, 200, 40), viewport, card)).toEqual({ x: 100, y: 388 });
	});

	it('clamps x so the card keeps 12 px inside the viewport on both sides', () => {
		expect(placeCard(r(-50, 100, 200, 40), viewport, card).x).toBe(12);
		expect(placeCard(r(950, 100, 200, 40), viewport, card).x).toBe(1024 - 320 - 12);
	});

	it('a target wider than the viewport still yields an on-screen card', () => {
		expect(placeCard(r(-200, 100, 1400, 40), viewport, card).x).toBe(12);
	});

	it('a viewport shorter than the card keeps the card at the top edge', () => {
		expect(placeCard(r(100, 500, 200, 40), { width: 1024, height: 150 }, card).y).toBe(12);
	});
});
