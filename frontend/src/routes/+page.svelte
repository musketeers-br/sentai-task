<script lang="ts">
	import { onMount } from 'svelte';
	import { replaceState } from '$app/navigation';
	import { SvelteFlowProvider } from '@xyflow/svelte';
	import { api, describeError } from '$lib/api/client';
	import { session } from '$lib/api/session.svelte';
	import FlowCanvas from '$lib/canvas/FlowCanvas.svelte';
	import { FlowEditor } from '$lib/flow/editor.svelte';
	import Inspector from '$lib/inspector/Inspector.svelte';
	import Palette from '$lib/palette/Palette.svelte';
	import ScheduleDialog from '$lib/shell/ScheduleDialog.svelte';
	import SignIn from '$lib/shell/SignIn.svelte';
	import StatusBar from '$lib/shell/StatusBar.svelte';
	import TopBar from '$lib/shell/TopBar.svelte';
	import { theme } from '$lib/shell/theme.svelte';

	const editor = new FlowEditor();

	type Phase = { name: 'idle' } | { name: 'loading' } | { name: 'ready' } | { name: 'failed'; message: string };
	let phase = $state<Phase>({ name: 'idle' });
	let scheduling = $state(false);

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

		const flowId = new URLSearchParams(location.search).get('flow');
		if (flowId) {
			const flow = await api.getFlow(flowId);
			if (!flow.ok) {
				phase = { name: 'failed', message: describeError(flow.error) };
				return;
			}
			editor.load(flow.value);
		}
		phase = { name: 'ready' };
	}

	function syncUrl() {
		if (!editor.id || new URLSearchParams(location.search).get('flow') === editor.id) return;
		const url = new URL(location.href);
		url.searchParams.set('flow', editor.id);
		replaceState(url, {});
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

{#if phase.name === 'ready'}
	<div class="app">
		<TopBar
			{editor}
			user={session.user}
			onsave={save}
			onvalidate={validate}
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
