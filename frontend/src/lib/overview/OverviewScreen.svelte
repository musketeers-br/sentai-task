<script lang="ts">
	import { untrack } from 'svelte';
	import { api } from '$lib/api/client';
	import { refusalText, type CatalogPage } from '$lib/catalog/catalog';
	import type { StepTypeInfo } from '$lib/flow/document';
	import type { Finding } from '$lib/flow/report';
	import ParameterForm from '$lib/inspector/ParameterForm.svelte';
	import ResultPanel from '$lib/run/ResultPanel.svelte';
	import AreaCard from './AreaCard.svelte';
	import AttentionBand from './AttentionBand.svelte';
	import { attention, scheduleStrip, unreadSummary } from './attention';
	import ReadingView from './ReadingView.svelte';
	import ScheduleStrip from './ScheduleStrip.svelte';
	import UnreadSummary from './UnreadSummary.svelte';
	import { isInstanceArea, paramFindings, withCardReport, withSummary, type AreaCardView } from './overview';

	// Spec 019: the landing screen — spec 018's 11 areas from one summary read. Report cards run
	// their report on demand into the run's own viewer and keep the last result in memory only
	// (clarification Q2); report areas can become a scheduled one-step flow (US4).
	let {
		areaParam,
		registry,
		onarea,
		onscheduled,
		onlink
	}: {
		/** The `area` query value: the detail view shown, or null for the cards. */
		areaParam: string | null;
		registry: StepTypeInfo[];
		onarea: (area: string | null) => void;
		/** A flow was created from a card: open it, and the schedule dialog when it validated clean. */
		onscheduled: (flowId: string, hasErrors: boolean) => void;
		/** Spec 023: an attention action — an address on this app, e.g. the catalog filtered. */
		onlink: (query: string) => void;
	} = $props();

	type Screen = { kind: 'loading' } | { kind: 'cards'; cards: AreaCardView[] } | { kind: 'unreachable'; text: string } | { kind: 'refused'; text: string };
	let view = $state<Screen>({ kind: 'loading' });
	let running = $state<Record<string, boolean>>({});
	let parameters = $state<Record<string, Record<string, unknown>>>({});
	let findings = $state<Record<string, Finding[]>>({});
	let editing = $state<string | null>(null);
	let viewing = $state<{ area: string; label: string; report: unknown } | null>(null);
	let notice = $state<string | null>(null);

	const cards = $derived(view.kind === 'cards' ? view.cards : null);
	const detail = $derived(areaParam !== null && isInstanceArea(cards, areaParam) ? areaParam : null);
	const instanceCards = $derived(cards ? cards.filter((c) => c.group === 'instance') : []);
	const reportCards = $derived(cards ? cards.filter((c) => c.group === 'report') : []);

	// Spec 023 US3: the catalog is read beside the summary; each fails on its own (FR-026).
	type CatalogRead = { kind: 'loading' } | { kind: 'ready'; page: CatalogPage } | { kind: 'unread'; line: string };
	let catalogRead = $state<CatalogRead>({ kind: 'loading' });
	let summaryReadAt = $state<string | null>(null);

	const summaryLine = $derived(view.kind === 'unreachable' || view.kind === 'refused' ? view.text : null);
	const summaryDone = $derived(view.kind !== 'loading');
	const attentionView = $derived(
		!summaryDone || catalogRead.kind === 'loading'
			? null
			: attention({ cards, catalog: catalogRead.kind === 'ready' ? catalogRead.page : null, backupStepDeclared: registry.some((t) => t.category === 'backup') })
	);
	const strip = $derived(
		catalogRead.kind !== 'ready' || !summaryDone ? null : scheduleStrip(catalogRead.page.items, cards ? summaryReadAt : null)
	);
	const unread = $derived(
		unreadSummary({ cards, summary: summaryLine, catalog: catalogRead.kind === 'unread' ? catalogRead.line : null })
	);

	async function loadCatalog() {
		const result = await api.catalogTasks();
		catalogRead = result.ok ? { kind: 'ready', page: result.value } : { kind: 'unread', line: refusalText(result.error) };
	}

	function refresh() {
		void load();
		void loadCatalog();
	}

	async function load() {
		const result = await api.overviewSummary();
		if (result.ok) {
			const previous = view.kind === 'cards' ? view.cards : [];
			view = { kind: 'cards', cards: withSummary(previous, result.value) };
			// Each area's readAt is the instance clock at the summary read: the strip's "now".
			summaryReadAt = result.value[0]?.state.readAt ?? null;
		} else if (result.error.kind === 'network') {
			view = { kind: 'unreachable', text: result.error.message };
		} else {
			view = { kind: 'refused', text: refusalText(result.error) };
		}
	}

	$effect(() => {
		untrack(() => refresh());
	});

	function specsFor(stepType: string | null) {
		return registry.find((t) => t.type === stepType)?.parameters ?? [];
	}

	async function runReport(card: AreaCardView) {
		if (!card.stepType || running[card.area]) return;
		running = { ...running, [card.area]: true };
		notice = null;
		const result = await api.overviewReport(card.stepType, parameters[card.area] ?? {});
		running = { ...running, [card.area]: false };
		if (!result.ok) {
			if (result.error.kind === 'validation') {
				findings = { ...findings, [card.area]: paramFindings(result.error.report) };
				editing = card.area;
			} else notice = `${card.label}: ${refusalText(result.error)}`;
			return;
		}
		findings = { ...findings, [card.area]: [] };
		if (view.kind === 'cards') view = { kind: 'cards', cards: withCardReport(view.cards, card.area, result.value) };
		viewing = { area: card.area, label: card.label, report: result.value.report ?? { failureReason: result.value.failureReason } };
	}

	async function schedule(card: AreaCardView) {
		notice = null;
		const result = await api.overviewFlow(card.area, parameters[card.area] ?? {});
		if (!result.ok) {
			if (result.error.kind === 'validation') {
				findings = { ...findings, [card.area]: paramFindings(result.error.report) };
				editing = card.area;
			} else notice = `${card.label}: ${refusalText(result.error)}`;
			return;
		}
		onscheduled(result.value.flowId, result.value.hasErrors);
	}
</script>

{#if detail}
	<ReadingView area={detail} onback={() => onarea(null)} />
{:else}
	<section class="overview" aria-label="Overview">
		<div class="head">
			<h1>Overview</h1>
			<span class="count">Every management area of this instance, read now with your own credential.</span>
			<span class="spacer"></span>
			<button type="button" onclick={refresh}>Refresh</button>
		</div>
		<!-- Spec 023: what needs attention, above spec 019's cards; each part fails on its own. -->
		<div class="attention">
			<UnreadSummary {unread} />
			<AttentionBand view={attentionView} {onlink} />
			<ScheduleStrip result={strip} unreadLine={catalogRead.kind === 'unread' ? catalogRead.line : null} />
		</div>
		{#if notice}<p class="notice mono" data-testid="overview-notice">{notice}</p>{/if}
		{#if areaParam !== null && cards && !detail}
			<p class="notice">"{areaParam}" has no detail view; showing every area.</p>
		{/if}

		{#if view.kind === 'loading'}
			<p class="faint pad">Reading every area…</p>
		{:else if view.kind === 'unreachable' || view.kind === 'refused'}
			<div class="pad" data-testid="overview-unreachable">
				<p class="mono">{view.text}</p>
				<button type="button" onclick={() => void load()}>Retry</button>
			</div>
		{:else}
			<div class="scroll">
				<h2 class="label">INSTANCE RESOURCES</h2>
				<div class="grid">
					{#each instanceCards as card (card.area)}
						<AreaCard
							{card}
							running={false}
							onopen={() => onarea(card.area)}
							onrun={() => {}}
							onopenreport={() => {}}
							onschedule={() => {}}
							onretry={() => void load()}
						/>
					{/each}
				</div>
				<h2 class="label">SECURITY, WEB APPLICATIONS, ALERTS AND SECRETS</h2>
				<div class="grid">
					{#each reportCards as card (card.area)}
						<div class="report-card">
							<AreaCard
								{card}
								running={running[card.area] === true}
								onopen={() => {}}
								onrun={() => void runReport(card)}
								onopenreport={() => card.report && (viewing = { area: card.area, label: card.label, report: card.report.report })}
								onschedule={() => void schedule(card)}
								onretry={() => void load()}
							/>
							{#if specsFor(card.stepType).length > 0}
								<details open={editing === card.area}>
									<summary>Parameters</summary>
									<ParameterForm
										specs={specsFor(card.stepType)}
										parameters={parameters[card.area] ?? {}}
										findings={findings[card.area] ?? []}
										onchange={(p) => (parameters = { ...parameters, [card.area]: p })}
									/>
								</details>
							{/if}
						</div>
					{/each}
				</div>
			</div>
		{/if}
	</section>
	{#if viewing}
		<div class="viewer">
			<ResultPanel stepId={viewing.area} name={viewing.label} result={viewing.report} onclose={() => (viewing = null)} />
		</div>
	{/if}
{/if}

<style>
	.overview {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
		background: var(--color-ground);
		color: var(--color-text);
	}

	.head {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-section);
		padding: 10px var(--space-section);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
	}

	h1 {
		margin: 0;
		font-size: var(--size-title);
		font-weight: 600;
	}

	.count,
	.faint {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.mono {
		font-family: var(--font-mono);
	}

	.spacer {
		flex-grow: 1;
	}

	.pad,
	.notice {
		padding: 10px var(--space-section);
		margin: 0;
	}

	.attention {
		padding: 0 var(--space-section);
	}

	.scroll {
		overflow: auto;
		flex-grow: 1;
		padding: 0 var(--space-section) var(--space-section);
	}

	.label {
		margin: 16px 0 8px;
		font-size: var(--size-caption);
		font-weight: 600;
		letter-spacing: 0.06em;
		color: var(--color-text-muted);
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
		gap: 12px;
	}

	.report-card {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	details {
		font-size: var(--size-caption);
	}

	.viewer {
		position: fixed;
		top: 56px;
		right: 0;
		bottom: 0;
		width: min(520px, 100vw);
		overflow: auto;
		background: var(--color-surface);
		border-left: 1px solid var(--color-border);
		z-index: 20;
	}
	button {
		font: inherit;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 5px 8px;
	}

	button {
		cursor: pointer;
	}

	button:disabled {
		cursor: default;
		opacity: 0.6;
	}

</style>
