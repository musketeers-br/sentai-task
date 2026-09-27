<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { SvelteFlowProvider } from '@xyflow/svelte';
	import { api, describeError } from '$lib/api/client';
	import CatalogScreen from '$lib/catalog/CatalogScreen.svelte';
	import { session } from '$lib/api/session.svelte';
	import FlowCanvas from '$lib/canvas/FlowCanvas.svelte';
	import type { FlowDocument } from '$lib/flow/document';
	import { FlowEditor } from '$lib/flow/editor.svelte';
	import Inspector from '$lib/inspector/Inspector.svelte';
	import Palette from '$lib/palette/Palette.svelte';
	import RunScreen from '$lib/run/RunScreen.svelte';
	import DispatchDialog from '$lib/shell/DispatchDialog.svelte';
	import ScheduleDialog from '$lib/shell/ScheduleDialog.svelte';
	import SignIn from '$lib/shell/SignIn.svelte';
	import StatusBar from '$lib/shell/StatusBar.svelte';
	import TopBar from '$lib/shell/TopBar.svelte';
	import { screenOf, urlForScreen, type Screen } from '$lib/shell/screen';
	import { theme } from '$lib/shell/theme.svelte';

	const editor = new FlowEditor();

	type Phase = { name: 'idle' } | { name: 'loading' } | { name: 'ready' } | { name: 'failed'; message: string };
	let phase = $state<Phase>({ name: 'idle' });
	let scheduling = $state(false);
	/** The live-run view (UI-002): the run GUID plus the flow snapshot it draws. */
	let watching = $state<{ guid: string; flow: FlowDocument } | null>(null);
	/** Derived from the address, so back/forward, deep links and reloads all agree (FR-002). */
	const screen = $derived(screenOf(page.url));

	onMount(() => theme.init());

	$effect(() => {
		if (session.status === 'signed-in' && phase.name === 'idle') void boot();
	});

	// The flow id travels in the query string: ServeFiles has no directory-index or SPA
	// fallback, so /flows/[id] cannot be served (contracts/tracer-bullet-deployment.md).
	async function boot() {
		phase = { name: 'loading' };
		const types = await api.stepTypes();
		if (!types.ok) {
			phase = { name: 'failed', message: describeError(types.error) };
			return;
		}
		editor.registry = types.value;

		// Suggestions only — typing any category name is still allowed and validated server-side.
		const categories = await api.wqmCategoryNames();
		if (categories.ok) editor.wqmCategories = categories.value;

		const params = new URLSearchParams(location.search);
		const flowId = params.get('flow');
		if (flowId) {
			const flow = await api.getFlow(flowId);
			if (!flow.ok) {
				phase = { name: 'failed', message: describeError(flow.error) };
				return;
			}
			editor.load(flow.value);
			const runGuid = params.get('run');
			if (runGuid) watching = { guid: runGuid, flow: flow.value };
		}
		phase = { name: 'ready' };
	}

	function syncUrl() {
		const url = new URL(page.url);
		if (editor.id) url.searchParams.set('flow', editor.id);
		if (watching) url.searchParams.set('run', watching.guid);
		else url.searchParams.delete('run');
		if (url.search !== page.url.search) void goto(url, { replaceState: true, keepFocus: true, noScroll: true });
	}

	// The one FlowEditor instance stays alive across screens, so the open flow and its unsaved
	// edits survive a trip to the catalog.
	function navigate(to: Screen) {
		if (to !== screen) void goto(urlForScreen(page.url, to), { keepFocus: true, noScroll: true });
	}

	/** The catalog detail is addressable too (`task=<id>`), so back closes it. */
	function selectTask(taskId: number | null) {
		const url = new URL(page.url);
		if (taskId === null) url.searchParams.delete('task');
		else url.searchParams.set('task', String(taskId));
		void goto(url, { keepFocus: true, noScroll: true });
	}

	/** The canvas with only that flow open (FR-009). */
	function flowHref(flowId: string): string {
		const url = new URL(page.url);
		url.search = '';
		url.searchParams.set('flow', flowId);
		return `${url.pathname}${url.search}`;
	}

	function openFlow(flowId: string) {
		void goto(flowHref(flowId), { noScroll: true });
	}

	// The address names the open flow: when it names another one (a catalog origin link, or
	// history), that flow is loaded into the one editor.
	$effect(() => {
		const flowId = page.url.searchParams.get('flow');
		if (phase.name !== 'ready' || screen !== 'flows' || !flowId) return;
		untrack(() => {
			if (flowId !== editor.id) void switchFlow(flowId);
		});
	});

	async function switchFlow(flowId: string) {
		const flow = await api.getFlow(flowId);
		if (!flow.ok) {
			editor.notice = { tone: 'error', text: describeError(flow.error) };
			return;
		}
		watching = null;
		editor.load(flow.value);
	}

	let dispatchOpen = $state(false);

	function onDispatched(guid: string) {
		watching = { guid, flow: editor.toDocument() };
		syncUrl();
	}

	function backToFlow() {
		watching = null;
		syncUrl();
	}

	async function save() {
		if (await editor.save()) syncUrl();
	}

	async function validate() {
		await editor.validate();
		syncUrl();
	}

	function addFromPalette(type: string) {
		const lowest = editor.nodes.reduce((max, n) => Math.max(max, n.position.y), -180);
		editor.addStep(type, { x: 0, y: lowest + 180 });
	}

	function onkeydown(event: KeyboardEvent) {
		if ((event.ctrlKey || event.metaKey) && event.key === 's' && phase.name === 'ready') {
			event.preventDefault();
			void save();
		}
	}

	function signOut() {
		session.logout();
		phase = { name: 'idle' };
	}
</script>

<svelte:window {onkeydown} />
<svelte:head><title>{editor.name} — SentaiTask</title></svelte:head>

{#if phase.name === 'ready' && screen === 'catalog'}
	<div class="app">
		<TopBar
			{editor}
			{screen}
			onnavigate={navigate}
			user={session.user}
			onsave={save}
			onvalidate={validate}
			onrun={() => (dispatchOpen = true)}
			onschedule={() => (scheduling = true)}
			onsignout={signOut}
		/>
		<CatalogScreen taskParam={page.url.searchParams.get('task')} {flowHref} onselect={selectTask} onopenflow={openFlow} />
	</div>
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if phase.name === 'ready' && watching}
	{#key watching.guid}
		<RunScreen guid={watching.guid} flow={watching.flow} registry={editor.registry} onback={backToFlow} />
	{/key}
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if phase.name === 'ready'}
	<div class="app">
		<TopBar
			{editor}
			{screen}
			onnavigate={navigate}
			user={session.user}
			onsave={save}
			onvalidate={validate}
			onrun={() => (dispatchOpen = true)}
			onschedule={() => (scheduling = true)}
			onsignout={signOut}
		/>
		<div class="workspace">
			<Palette registry={editor.registry} onadd={addFromPalette} />
			<div class="canvas-area">
				<SvelteFlowProvider>
					<FlowCanvas {editor} />
				</SvelteFlowProvider>
			</div>
			<Inspector {editor} />
		</div>
		<StatusBar {editor} />
	</div>
	<ScheduleDialog {editor} bind:open={scheduling} />
	<DispatchDialog {editor} bind:open={dispatchOpen} ondispatched={onDispatched} />
	<datalist id="wqm-categories">
		{#each editor.wqmCategories as name (name)}<option value={name}></option>{/each}
	</datalist>
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if session.status !== 'signed-in'}
	<SignIn expired={session.status === 'expired'} />
{:else if phase.name === 'failed'}
	<main class="message" role="alert">
		<p>{phase.message}</p>
		<button type="button" onclick={() => (phase = { name: 'idle' })}>Try again</button>
	</main>
{:else}
	<main class="message"><p>Loading the step catalog…</p></main>
{/if}

<style>
	.app {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.workspace {
		display: flex;
		flex-grow: 1;
		min-height: 0;
	}

	.canvas-area {
		flex-grow: 1;
		min-width: 0;
	}

	.overlay {
		position: fixed;
		inset: 0;
		background: color-mix(in srgb, var(--color-ground) 70%, transparent);
	}

	.message {
		display: grid;
		place-content: center;
		gap: 12px;
		height: 100%;
		font-size: var(--size-body);
		color: var(--color-text-muted);
		text-align: center;
	}

	.message button {
		font: inherit;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 12px;
		cursor: pointer;
	}
</style>
