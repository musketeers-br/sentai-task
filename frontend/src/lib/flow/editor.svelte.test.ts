import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { session } from '$lib/api/session.svelte';
import type { FlowDocument, StepTypeInfo } from './document';
import { FlowEditor } from './editor.svelte';

// spec 010 US1 (data-model §2): Save as, New flow (reset), the rename notice, the conflict hint.

type Call = { method: string; url: string; body: unknown };
let calls: Call[] = [];
let respond: (call: Call) => Response;

const json = (status: number, body: unknown) =>
	new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

beforeEach(async () => {
	calls = [];
	vi.stubGlobal('fetch', async (input: RequestInfo | URL, init: RequestInit = {}) => {
		const call = { method: init.method ?? 'GET', url: String(input), body: init.body ? JSON.parse(String(init.body)) : undefined };
		if (call.url.endsWith('/api/admin/login')) {
			return json(200, { access_token: 'access', refresh_token: 'refresh', sub: '_SYSTEM', iat: 1000, exp: 1060 });
		}
		calls.push(call);
		return respond(call);
	});
	await session.login('_SYSTEM', 'pw');
});

afterEach(() => {
	session.logout();
	vi.unstubAllGlobals();
});

const sizeReport: StepTypeInfo = {
	type: 'db-size-report',
	className: 'sentai.steps.DatabaseSizeReport',
	category: 'storage',
	destructive: false,
	pausable: false,
	available: true,
	executor: 'in-process',
	parameters: []
};

const savedA: FlowDocument = {
	id: '5',
	name: 'A',
	revision: 1,
	savedAt: '2026-09-27 10:00:00',
	defaultCategory: 'Default',
	steps: [
		{
			id: '01',
			type: 'db-size-report',
			taskName: 'Sizes',
			namespace: '%SYS',
			databaseDirectory: '',
			runAsUser: '',
			timeoutMinutes: null,
			wqmCategory: 'Default',
			customClass: '',
			parameters: {}
		}
	],
	edges: [],
	positions: { '01': { x: 40, y: 40 } }
};

function editorWithA(): FlowEditor {
	const editor = new FlowEditor();
	editor.registry = [sizeReport];
	editor.load(savedA);
	return editor;
}

/** What POST /flows answers: the definition it was given, with an id and revision 1. */
const created = (id: string) => (call: Call) => {
	const def = call.body as Record<string, unknown>;
	return json(201, { ...def, id, revision: 1, savedAt: '2026-09-27 10:05:00', savedBy: '_SYSTEM' });
};

describe('FlowEditor.saveAs', () => {
	it('POSTs the current canvas — unsaved edits included — under the new name, then holds the new flow', async () => {
		const editor = editorWithA();
		editor.addStep('db-size-report', { x: 40, y: 260 });
		respond = created('6');

		const result = await editor.saveAs('B');

		expect(result.ok).toBe(true);
		expect(calls.map((c) => `${c.method} ${c.url}`)).toEqual(['POST /csp/sentai/api/v1/flows']);
		const body = calls[0].body as { name: string; steps: unknown[]; canvasGeometry: { nodes: object } };
		expect(body.name).toBe('B');
		expect(body.steps).toHaveLength(2);
		expect(Object.keys(body.canvasGeometry.nodes)).toEqual(['01', '02']);
		expect(editor.id).toBe('6');
		expect(editor.name).toBe('B');
		expect(editor.savedName).toBe('B');
		expect(editor.revision).toBe(1);
		expect(editor.dirty).toBe(false);
	});

	it('a refusal leaves the editor exactly as it was and returns the platform\'s words', async () => {
		const editor = editorWithA();
		editor.addStep('db-size-report', { x: 40, y: 260 });
		respond = () => json(409, { status: 409, title: 'Conflict', detail: 'A flow with this name already exists' });

		const result = await editor.saveAs('Taken');

		expect(result.ok).toBe(false);
		if (!result.ok) expect(result.error).toMatchObject({ kind: 'problem', status: 409, detail: 'A flow with this name already exists' });
		expect(editor.id).toBe('5');
		expect(editor.name).toBe('A');
		expect(editor.revision).toBe(1);
		expect(editor.dirty).toBe(true);
		expect(editor.steps).toHaveLength(2);
		expect(editor.notice).toBeNull();
	});
});

describe('FlowEditor.reset', () => {
	it('starts an empty, unsaved draft with the given name', () => {
		const editor = editorWithA();
		editor.notice = { tone: 'error', text: 'x' };
		editor.reset('Untitled flow 2026-09-27 10:11:12');
		expect(editor.nodes).toEqual([]);
		expect(editor.edges).toEqual([]);
		expect(editor.id).toBeNull();
		expect(editor.revision).toBe(0);
		expect(editor.savedAt).toBeNull();
		expect(editor.savedName).toBeNull();
		expect(editor.report).toBeNull();
		expect(editor.notice).toBeNull();
		expect(editor.dirty).toBe(false);
		expect(editor.name).toBe('Untitled flow 2026-09-27 10:11:12');
	});
});

describe('FlowEditor.renaming (FR-005)', () => {
	it('is true only for a saved flow whose name field differs from its saved name', () => {
		const draft = new FlowEditor();
		draft.name = 'anything';
		expect(draft.renaming).toBe(false);

		const editor = editorWithA();
		expect(editor.renaming).toBe(false);
		editor.name = 'A2';
		expect(editor.renaming).toBe(true);
		editor.name = '  A ';
		expect(editor.renaming).toBe(false);
	});
});

describe('FlowEditor.conflictHint', () => {
	it('is set by a 409 on Save flow and cleared by the next successful save', async () => {
		const editor = editorWithA();
		editor.touch('cosmetic');
		respond = () => json(409, { status: 409, title: 'Conflict', detail: 'Flow was saved by someone else since it was loaded' });
		expect(await editor.save()).toBe(false);
		expect(editor.notice?.text).toBe('Flow was saved by someone else since it was loaded');
		expect(editor.conflictHint).toBe(true);

		respond = (call) => json(200, { ...(call.body as object), id: '5', revision: 2, savedAt: '2026-09-27 10:06:00' });
		expect(await editor.save()).toBe(true);
		expect(editor.conflictHint).toBe(false);
		expect(editor.savedName).toBe('A');
	});
});
