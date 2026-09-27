// The Task catalog's view models (spec 007 data-model.md). This module and src/lib/api/client.ts
// are the only ones that know the spec 006 wire shape; components receive only these types.

/** The keys of a spec 006 catalog item this screen reads so far. */
export interface WireCatalogTask {
	taskId: number | string;
	name: string;
	namespace: string;
}

export interface WireCatalogPage {
	total: number | string;
	matched: number | string;
	items: WireCatalogTask[];
}

export interface CatalogTaskView {
	taskId: number;
	name: string;
	namespace: string;
}

export interface CatalogPage {
	total: number;
	matched: number;
	items: CatalogTaskView[];
}

export function fromWireCatalogTask(w: WireCatalogTask): CatalogTaskView {
	return { taskId: Number(w.taskId), name: w.name, namespace: w.namespace };
}

export function fromWireCatalogPage(w: WireCatalogPage): CatalogPage {
	return {
		total: Number(w.total),
		matched: Number(w.matched),
		items: (w.items ?? []).map(fromWireCatalogTask)
	};
}
