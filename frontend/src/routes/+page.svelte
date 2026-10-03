<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { beforeNavigate, goto } from '$app/navigation';
	import { page } from '$app/state';
	import { SvelteFlowProvider } from '@xyflow/svelte';
	import { api, describeError } from '$lib/api/client';
	import { filtersFromUrl, withFilters, type CatalogFilters, type StepDraft } from '$lib/catalog/catalog';
	import CatalogScreen from '$lib/catalog/CatalogScreen.svelte';
	import TargetsScreen from '$lib/targets/TargetsScreen.svelte';
	import { session } from '$lib/api/session.svelte';
	import FlowCanvas from '$lib/canvas/FlowCanvas.svelte';
	import type { FlowDocument } from '$lib/flow/document';
	import { FlowEditor } from '$lib/flow/editor.svelte';
	import { afterSave, decide, needsGuard, type GuardChoice, type PendingSwitch } from '$lib/flows/guard';
	import { defaultFlowName } from '$lib/flows/list';
	import RunbookGallery from '$lib/flows/RunbookGallery.svelte';
	import { EXAMPLE_RUNBOOK, useRunbook, type Runbook } from '$lib/flows/runbooks';
	import EmptyCanvas from '$lib/flows/EmptyCanvas.svelte';
	import FlowBar from '$lib/flow/FlowBar.svelte';
	import { exampleAvailable } from '$lib/flows/example';
	import OpenFlowDialog from '$lib/flows/OpenFlowDialog.svelte';
	import GettingStartedDialog from '$lib/guide/GettingStartedDialog.svelte';
	import { guide, shouldAutoOpen } from '$lib/guide/guide.svelte';
	import SaveAsDialog from '$lib/flows/SaveAsDialog.svelte';
	import UnsavedChangesDialog from '$lib/flows/UnsavedChangesDialog.svelte';
	import Inspector from '$lib/inspector/Inspector.svelte';
	import Palette from '$lib/palette/Palette.svelte';
	import RunScreen from '$lib/run/RunScreen.svelte';
	import RunsScreen from '$lib/runs/RunsScreen.svelte';
	import { queryFromUrl, urlForQuery, urlForRun, type RunSummaryView, type RunsQuery } from '$lib/runs/runs';
	import DispatchDialog from '$lib/shell/DispatchDialog.svelte';
	import ScheduleDialog from '$lib/shell/ScheduleDialog.svelte';
	import SignIn from '$lib/shell/SignIn.svelte';
	import StatusBar from '$lib/shell/StatusBar.svelte';
	import TopBar from '$lib/shell/TopBar.svelte';
	import Tour from '$lib/tour/Tour.svelte';
	import { tour } from '$lib/tour/tour.svelte';
	import { screenOf, urlForArea, urlForScreen, type Screen } from '$lib/shell/screen';
	import OverviewScreen from '$lib/overview/OverviewScreen.svelte';
	import { theme } from '$lib/shell/theme.svelte';

	const editor = new FlowEditor();

	type Phase = { name: 'idle' } | { name: 'loading' } | { name: 'ready' } | { name: 'failed'; message: string };
	let phase = $state<Phase>({ name: 'idle' });
	let scheduling = $state(false);
	/** The live-run view (UI-002): the run GUID plus the flow snapshot it draws. */
	let watching = $state<{ guid: string; flow: FlowDocument } | null>(null);
	/** Derived from the address, so back/forward, deep links and reloads all agree (FR-002). */
	const screen = $derived(screenOf(page.url));

	onMount(() => {
		theme.init();
		// Spec 010 US3: keep the tab's sign-in across reloads; the address then restores the place.
		session.attachPageLifecycle(window);
		void session.restore();
	});

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
		// Spec 009: the targets *Run on* offers; an unreadable list offers none.
		await loadTargets();

		const params = new URLSearchParams(location.search);
		const flowId = params.get('flow');
		if (flowId) {
			const flow = await api.getFlow(flowId);
			if (!flow.ok) {
				// Spec 010 D-8: not a blank failure — the platform's reason, and Open flow… / New flow.
				editor.notice = { tone: 'error', text: describeError(flow.error) };
				unreadable = flowId;
				phase = { name: 'ready' };
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

	/** The Targets screen's selection is addressable (`target=<name>`), like the catalog's. */
	function selectTarget(name: string | null) {
		const url = new URL(page.url);
		if (name === null) url.searchParams.delete('target');
		else url.searchParams.set('target', name);
		void goto(url, { keepFocus: true, noScroll: true });
	}

	/** Spec 009: *Run on* offers the registered targets; re-read after the Targets screen changes. */
	async function loadTargets() {
		const targets = await api.listTargets();
		if (targets.ok) editor.targets = targets.value;
	}

	/** Spec 023: the catalog's filters live in the address, so Overview can link to them. */
	function followCatalogFilters(filters: CatalogFilters) {
		const next = withFilters(page.url, filters);
		if (next.href !== page.url.href) void goto(next, { replaceState: true, keepFocus: true, noScroll: true });
	}

	/** Spec 023 FR-018: the task's step type joins the open flow, which becomes unsaved. */
	function addTaskToFlow(step: StepDraft) {
		const lowest = editor.nodes.reduce((max, n) => Math.max(max, n.position.y), -180);
		const node = editor.addStep(step.type, { x: 0, y: lowest + 180 });
		if (!node) return;
		const fields = { ...(step.namespace ? { namespace: step.namespace } : {}), ...(step.runAsUser ? { runAsUser: step.runAsUser } : {}) };
		if (Object.keys(fields).length > 0) editor.updateStep(node.id, fields);
		navigate('flows');
	}

	/** The catalog detail is addressable too (`task=<id>`), so back closes it. */
	function selectTask(taskId: number | null) {
		const url = new URL(page.url);
		if (taskId === null) url.searchParams.delete('task');
		else url.searchParams.set('task', String(taskId));
		void goto(url, { keepFocus: true, noScroll: true });
	}

	/** Spec 016: the run view's step detail is addressable (`step=<id>`), so back closes it. */
	function selectStep(stepId: string | null) {
		const url = new URL(page.url);
		if (stepId === null) url.searchParams.delete('step');
		else url.searchParams.set('step', stepId);
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
		if (phase.name !== 'ready' || screen !== 'flows' || !flowId || flowId === unreadable) return;
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
		unreadable = null;
		editor.load(flow.value);
		// Spec 012: a run opened from the Runs screen arrives with its flow; show it once loaded.
		const runGuid = page.url.searchParams.get('run');
		if (runGuid) watching = { guid: runGuid, flow: flow.value };
	}

	// Spec 012: the address names a run of the flow already open (a run of the same flow opened
	// from the Runs screen, or back/forward): show it.
	$effect(() => {
		const runGuid = page.url.searchParams.get('run');
		const flowId = page.url.searchParams.get('flow');
		if (phase.name !== 'ready' || screen !== 'flows' || !runGuid) return;
		untrack(() => {
			if (flowId === editor.id && watching?.guid !== runGuid) watching = { guid: runGuid, flow: editor.toDocument() };
		});
	});

	/** Spec 019: an Overview card's detail view is addressable (`area=<id>`), so back closes it. */
	function selectArea(area: string | null) {
		void goto(urlForArea(page.url, area), { keepFocus: true, noScroll: true });
	}

	/**
	 * Spec 019 US4 (research R-5): a flow created from an Overview card opens in the editor, and
	 * the schedule dialog opens over it once it is loaded — only when it validated clean.
	 */
	let scheduleWhenLoaded = $state<string | null>(null);
	function scheduleCreated(flowId: string, hasErrors: boolean) {
		scheduleWhenLoaded = hasErrors ? null : flowId;
		void goto(flowHref(flowId), { noScroll: true });
	}
	$effect(() => {
		if (scheduleWhenLoaded !== null && editor.id === scheduleWhenLoaded && screen === 'flows') {
			untrack(() => {
				scheduleWhenLoaded = null;
				scheduling = true;
			});
		}
	});

	/** Spec 012 US2: the Runs screen's filters live in the address (FR-007). */
	function setRunsQuery(query: RunsQuery) {
		void goto(urlForQuery(page.url, query), { keepFocus: true, noScroll: true });
	}

	/** A past run opens in the run view with its flow; switching flows goes through the guard. */
	function openRun(run: RunSummaryView) {
		void guarded({ kind: 'address', url: urlForRun(page.url, run) });
	}

	/** Spec 012 FR-010: the Runs screen filtered to the open flow. */
	function runHistory() {
		if (editor.id) void goto(urlForQuery(page.url, { flow: editor.id }), { noScroll: true });
	}

	let dispatchOpen = $state(false);
	let saveAsOpen = $state(false);
	let openListOpen = $state(false);
	/** Spec 010 D-8: the flow the address named could not be read; the canvas offers a way on. */
	let unreadable = $state<string | null>(null);
	/** Spec 022 FR-012: *Start from scratch* (and a successful Use) hide the gallery for the session. */
	let galleryDismissed = $state(false);
	// Spec 022 FR-001: the gallery replaces the empty canvas whenever no flow is open — also on
	// an instance with saved flows (the old `noFlows` term is gone; that was the demo's gap).
	const showGallery = $derived(
		unreadable === null && editor.id === null && editor.steps.length === 0 && !galleryDismissed
	);
	/** Spec 023 FR-008: the template card is offered only when the example's step types are
	 *    declared, available and non-destructive (spec 010 FR-019). */
	const showExample = $derived(exampleAvailable(editor.registry));

	// --- Spec 010 FR-006: the one unsaved-changes guard --------------------------------------
	// Every switch away from the open flow goes through `guarded`: New flow, Open flow…, Open
	// example flow, and (via beforeNavigate) back/forward or a link that changes `flow`.
	let guard = $state<{ pending: PendingSwitch; busy: boolean; message: string | null } | null>(null);
	let guardOpen = $state(false);
	/** Set just before a navigation the guard already approved, so it is not asked twice. */
	let bypassGuard = false;

	async function guarded(pending: PendingSwitch) {
		if (!needsGuard(editor.dirty)) return perform(pending);
		guard = { pending, busy: false, message: null };
		guardOpen = true;
	}

	async function onGuardChoice(choice: GuardChoice) {
		if (!guard) return;
		let step = decide(choice);
		if (step.next === 'save-then-proceed') {
			guard.busy = true;
			const ok = await editor.save();
			guard.busy = false;
			step = afterSave(ok);
			// A refused save keeps the operator here, with the platform's words (FR-008).
			if (step.next === 'stay') {
				guard.message = editor.notice?.text ?? 'The flow could not be saved.';
				return;
			}
		}
		const pending = guard.pending;
		guard = null;
		guardOpen = false;
		if (step.next === 'proceed') await perform(pending);
	}

	async function perform(pending: PendingSwitch) {
		switch (pending.kind) {
			case 'new':
				return newFlowNow();
			case 'open':
				return navigateApproved(flowHref(pending.flowId));
			case 'runbook':
				return openRunbookNow(pending.runbook);
			case 'address':
				return navigateApproved(pending.url);
		}
	}

	async function navigateApproved(to: string | URL) {
		bypassGuard = true;
		try {
			await goto(to, { noScroll: true });
		} finally {
			bypassGuard = false;
		}
	}

	beforeNavigate((navigation) => {
		if (bypassGuard || !navigation.to || navigation.type === 'leave' || phase.name !== 'ready') return;
		const from = page.url.searchParams.get('flow');
		const to = navigation.to.url.searchParams.get('flow');
		if (from === to || !needsGuard(editor.dirty)) return;
		navigation.cancel();
		void guarded({ kind: 'address', url: navigation.to.url });
	});

	/** Spec 010 FR-007: an empty draft with a fresh unique name; the address drops the old flow. */
	async function newFlowNow() {
		unreadable = null;
		const flows = await api.listFlows();
		editor.reset(defaultFlowName(new Date(), flows.ok ? flows.value.map((f) => f.name) : []));
		watching = null;
		const url = new URL(page.url);
		url.searchParams.delete('flow');
		url.searchParams.delete('run');
		// Spec 019: without a flow the address must still name the editor, not the landing screen.
		url.searchParams.set('view', 'flows');
		await goto(url, { keepFocus: true, noScroll: true });
	}

	/**
	 * Spec 022 FR-006: the runbook opens as a flow — the existing one of that name, or a new one
	 * created through the ordinary flow-creation path under the operator's own sign-in (spec 010
	 * FR-017's machine, generalized). A refusal surfaces verbatim (FR-009); a success is a saved,
	 * runnable flow (FR-010) — the gallery has done its job and steps aside.
	 */
	async function openRunbookNow(runbook: Runbook) {
		const result = await useRunbook(api, runbook);
		if (!result.ok) {
			editor.notice = { tone: 'error', text: describeError(result.error) };
			return;
		}
		galleryDismissed = true;
		unreadable = null;
		await navigateApproved(flowHref(result.value));
	}

	/** Spec 010 FR-004: the new flow is open; pushing its address lets Back return to the original. */
	function onSavedAs(flowId: string) {
		void goto(flowHref(flowId), { keepFocus: true, noScroll: true });
	}

	function onDispatched(guid: string) {
		watching = { guid, flow: editor.toDocument() };
		syncUrl();
	}

	function backToFlow() {
		watching = null;
		// Spec 012 D-7: a run opened from the Runs screen goes back to it, with its filters.
		if (page.url.searchParams.get('from') === 'runs') {
			void goto(urlForQuery(page.url, queryFromUrl(page.url)), { noScroll: true });
			return;
		}
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
		const command = event.ctrlKey || event.metaKey;
		if (command && event.shiftKey && event.key.toLowerCase() === 's' && phase.name === 'ready' && screen === 'flows') {
			event.preventDefault();
			saveAsOpen = true;
			return;
		}
		if (command && !event.shiftKey && event.key.toLowerCase() === 'o' && phase.name === 'ready' && screen === 'flows' && !watching) {
			event.preventDefault();
			openListOpen = true;
			return;
		}
		if (command && event.key === 's' && phase.name === 'ready') {
			event.preventDefault();
			void save();
		}
	}

	// Spec 022 FR-007 (data-model §5): the card verdicts read the registered targets fresh every
	// time the gallery is shown — data the page already keeps for *Run on* (spec 009), never a
	// permission cache (Constitution III).
	$effect(() => {
		if (showGallery) untrack(() => void loadTargets());
	});

	// Spec 010 FR-020: once the canvas is ready after a sign-in typed with the password — never after
	// a reload that kept the sign-in — unless dismissed in this browser or already shown this visit.
	$effect(() => {
		if (phase.name !== 'ready') return;
		untrack(() => {
			if (shouldAutoOpen({ origin: session.origin, dismissed: guide.dismissed(), shownThisVisit: guide.shownThisVisit })) {
				guide.autoOpen();
			}
		});
	});

	/**
	 * Spec 022 FR-013: every ready-made path leads to the gallery. The guide's step 2 and the
	 * *Open flow…* dialog's entry land on the empty canvas with the gallery showing — through
	 * the guard when the open flow has unsaved edits, like *New flow*.
	 */
	function openRunbooks() {
		guide.close(); // the guide's entry; the *Open flow…* dialog closes itself (startBrowse)
		galleryDismissed = false;
		void guarded({ kind: 'new' });
	}

	// Spec 021 FR-011: the tour closes the moment the canvas stops being editable — the four
	// ways out (plan D-7, research R-5) — so the veil can never sit over a refusal, a run view
	// or the sign-in overlay, and no ghost tour reappears when the canvas comes back.
	$effect(() => {
		if (phase.name !== 'ready' || screen !== 'flows' || watching !== null || session.status === 'expired') {
			tour.close();
		}
	});

	function signOut() {
		guide.close();
		guide.resetVisit();
		tour.close();
		// Spec 022 (US4 scenario 4.5): the gallery's dismissal ends with the operator's session —
		// the next sign-in, often another visitor of the shared demo account, starts at the gallery.
		galleryDismissed = false;
		session.logout();
		phase = { name: 'idle' };
	}
</script>

<svelte:window {onkeydown} />
<svelte:head><title>{editor.name} — SentaiTask</title></svelte:head>

{#if phase.name === 'ready' && screen === 'overview'}
	<div class="app">
		<TopBar {screen} onnavigate={navigate} user={session.user} onhelp={() => guide.openFromHelp()} onsignout={signOut} />
		<main class="main">
			<OverviewScreen
				areaParam={page.url.searchParams.get('area')}
				registry={editor.registry}
				onarea={selectArea}
				onscheduled={scheduleCreated}
				onlink={(query) => void goto(new URL(query, page.url), { noScroll: true })}
			/>
		</main>	</div>
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if phase.name === 'ready' && screen === 'targets'}
	<div class="app">
		<TopBar {screen} onnavigate={navigate} user={session.user} onhelp={() => guide.openFromHelp()} onsignout={signOut} />
		<main class="main">
			<TargetsScreen targetParam={page.url.searchParams.get('target')} onselect={selectTarget} onchanged={loadTargets} />
		</main>	</div>
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if phase.name === 'ready' && screen === 'runs'}
	<div class="app">
		<TopBar {screen} onnavigate={navigate} user={session.user} onhelp={() => guide.openFromHelp()} onsignout={signOut} />
		<main class="main">
			<RunsScreen query={queryFromUrl(page.url)} onquery={setRunsQuery} onopen={openRun} />
		</main>	</div>
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if phase.name === 'ready' && screen === 'catalog'}
	<div class="app">
		<TopBar {screen} onnavigate={navigate} user={session.user} onhelp={() => guide.openFromHelp()} onsignout={signOut} />
		<main class="main">
			<CatalogScreen
				taskParam={page.url.searchParams.get('task')}
				initialFilters={filtersFromUrl(page.url)}
				registry={editor.registry}
				{flowHref}
				onselect={selectTask}
				onopenflow={openFlow}
				onaddtoflow={addTaskToFlow}
				onfilters={followCatalogFilters}
			/>
		</main>	</div>
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if phase.name === 'ready' && watching}
	{#key watching.guid}
		<RunScreen
			guid={watching.guid}
			flow={watching.flow}
			registry={editor.registry}
			onback={backToFlow}
			backLabel={page.url.searchParams.get('from') === 'runs' ? 'Back to runs' : 'Back to flow'}
			step={page.url.searchParams.get('step')}
			onselectstep={selectStep}
		/>
	{/key}
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if phase.name === 'ready'}
	<div class="app">
		<TopBar {screen} onnavigate={navigate} user={session.user} onhelp={() => guide.openFromHelp()} onsignout={signOut} />
		<FlowBar
			{editor}
			onopen={() => (openListOpen = true)}
			onsave={save}
			onsaveas={() => (saveAsOpen = true)}
			onnew={() => void guarded({ kind: 'new' })}
			onvalidate={validate}
			onrun={() => (dispatchOpen = true)}
			onschedule={() => (scheduling = true)}
			onhistory={runHistory}
		/>
		<div class="workspace">
			<Palette registry={editor.registry} onadd={addFromPalette} />
			<div class="canvas-area">
				<SvelteFlowProvider>
					<FlowCanvas {editor} />
				</SvelteFlowProvider>
				<!-- Spec 021 FR-001: the tour's only entry — pinned to the canvas (the top bar
				     already fits exactly at 1440 px, plan risk R-4), visible, one action. -->
				<button type="button" class="canvas-tour" data-testid="tour-button" onclick={() => tour.start()}>
					Tour
				</button>
			{#if showGallery}
				<!-- Spec 022 FR-001: the gallery replaces the empty canvas whenever no flow is open;
				     the unreadable-flow panel below still wins when it applies. -->
				<RunbookGallery
					registry={editor.registry}
					targets={editor.targets.map((t) => t.name)}
					onuse={(runbook) => void guarded({ kind: 'runbook', runbook })}
					onstartblank={() => (galleryDismissed = true)}
				/>
			{:else if unreadable === null && editor.steps.length === 0}
				<!-- Spec 023 FR-007–FR-009: every other empty flow says how to start — the blank
				     canvas after *Start from scratch*, or an open flow with no steps. -->
				<EmptyCanvas
					showTemplate={showExample}
					ontemplate={() => void guarded({ kind: 'runbook', runbook: EXAMPLE_RUNBOOK })}
					onimport={() => navigate('catalog')}
				/>
			{/if}
				{#if unreadable !== null && editor.id === null && editor.steps.length === 0}
					<div class="canvas-panel" data-testid="flow-unreadable">
						<p>This flow could not be opened. The reason is in the status bar.</p>
						<div class="panel-actions">
							<button type="button" onclick={() => (openListOpen = true)}>Open flow…</button>
							<button type="button" onclick={() => void guarded({ kind: 'new' })}>New flow</button>
						</div>
					</div>
				{/if}
			</div>
			<Inspector {editor} />
		</div>
		<StatusBar {editor} />
	</div>
	<ScheduleDialog {editor} bind:open={scheduling} />
	<SaveAsDialog {editor} bind:open={saveAsOpen} onsaved={onSavedAs} />
	<OpenFlowDialog
		bind:open={openListOpen}
		currentId={editor.id}
		onpick={(flowId) => void guarded({ kind: 'open', flowId })}
		onnew={() => void guarded({ kind: 'new' })}
		onbrowse={openRunbooks}
	/>
	<UnsavedChangesDialog
		bind:open={guardOpen}
		name={editor.name}
		busy={guard?.busy ?? false}
		message={guard?.message ?? null}
		onchoose={(choice) => void onGuardChoice(choice)}
	/>
	<DispatchDialog {editor} bind:open={dispatchOpen} ondispatched={onDispatched} />
	<!-- Spec 021: the coach-mark tour's overlay; the Tour button in the top bar starts it. -->
	<Tour />
	<datalist id="wqm-categories">
		{#each editor.wqmCategories as name (name)}<option value={name}></option>{/each}
	</datalist>
	{#if session.status === 'expired'}
		<div class="overlay"><SignIn expired /></div>
	{/if}
{:else if session.status === 'restoring'}
	<main class="message" role="status"><p>Signing you back in…</p></main>
{:else if session.status !== 'signed-in'}
	<SignIn expired={session.status === 'expired'} notice={session.ended} />
{:else if phase.name === 'failed'}
	<main class="message" role="alert">
		<p>{phase.message}</p>
		<button type="button" onclick={() => (phase = { name: 'idle' })}>Try again</button>
	</main>
{:else}
	<main class="message"><p>Loading the step catalog…</p></main>
{/if}

{#if phase.name === 'ready' && session.status === 'signed-in'}
	<GettingStartedDialog onbrowse={openRunbooks} />
{/if}

<style>
	.app {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	/* Spec 023 follow-up (axe landmark-one-main, region): each screen's content is the page's main. */
	.main {
		display: flex;
		flex-direction: column;
		flex: 1 1 auto;
		min-height: 0;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}

	.workspace {
		display: flex;
		flex-grow: 1;
		min-height: 0;
	}

	.canvas-area {
		position: relative;
		flex-grow: 1;
		min-width: 0;
	}

	/* Spec 021 FR-001: the tour button shares the canvas' top-right corner — free of SvelteFlow's
	   Panels (top-left), Controls (bottom-left) and MiniMap (bottom-right).
	   Spec 022: z-index 5 keeps it above the runbook gallery that now covers the empty canvas. */
	.canvas-tour {
		position: absolute;
		top: 10px;
		right: 12px;
		z-index: 5;
		font: inherit;
		font-size: var(--size-caption);
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 5px 10px;
		cursor: pointer;
	}

	/* Spec 010: a card over the empty canvas (the unreadable-flow panel; later the invitation). */
	.canvas-panel {
		position: absolute;
		top: 50%;
		left: 50%;
		z-index: 4;
		display: flex;
		flex-direction: column;
		gap: 12px;
		max-width: 360px;
		padding: 20px 22px;
		transform: translate(-50%, -50%);
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: var(--color-card-shadow);
	}

	.canvas-panel p {
		margin: 0;
		line-height: 1.5;
	}

	.panel-actions {
		display: flex;
		gap: 8px;
	}

	.panel-actions button {
		font: inherit;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 12px;
		cursor: pointer;
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
