import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { Tour } from './tour.svelte';

// spec 021 US1/US2 (data-model §2): start, next, skip, finish, close — and nothing else. The
// tour has no storage and no first-use detection (FR-009, FR-010), so every launch is identical.

describe('Tour', () => {
	it('start() opens at step 1 from any prior state', () => {
		const tour = new Tour();
		tour.start();
		tour.next();
		tour.next();
		expect(tour.step).toBe(3);
		tour.start();
		expect(tour.open).toBe(true);
		expect(tour.step).toBe(1);
	});

	it('next() advances one mark and clamps at the last (FR-005)', () => {
		const tour = new Tour();
		tour.start();
		for (let i = 0; i < 10; i++) tour.next();
		expect(tour.step).toBe(3);
	});

	it('next() never opens a closed tour by itself', () => {
		const tour = new Tour();
		tour.next();
		expect(tour.open).toBe(false);
	});

	it('skip(), finish() and close() all end the tour; close() is safe when already closed', () => {
		for (const end of ['skip', 'finish', 'close'] as const) {
			const tour = new Tour();
			tour.start();
			tour[end]();
			expect(tour.open).toBe(false);
		}
		const tour = new Tour();
		expect(() => tour.close()).not.toThrow();
		expect(tour.open).toBe(false);
	});

	it('a second start() after finish() is identical to the first launch (FR-010)', () => {
		const tour = new Tour();
		tour.start();
		tour.next();
		tour.finish();
		tour.start();
		expect(tour.open).toBe(true);
		expect(tour.step).toBe(1);
	});

	it('persists nothing — the module never touches browser storage (FR-010)', () => {
		const source = readFileSync(fileURLToPath(new URL('./tour.svelte.ts', import.meta.url)), 'utf8');
		expect(source).not.toMatch(/localStorage|sessionStorage/);
	});
});
