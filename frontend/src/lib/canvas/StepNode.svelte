<script lang="ts">
	import { Handle, Position, useNodeConnections, type NodeProps } from '@xyflow/svelte';
	import type { StepFlowNode } from '$lib/flow/editor.svelte';
	import { getEditorContext } from '$lib/flow/context';

	let { id, data, selected }: NodeProps<StepFlowNode> = $props();

	const editor = getEditorContext();
	const findings = $derived(editor.findingsFor(id));

	const incoming = useNodeConnections({ handleType: 'target' });
	const outgoing = useNodeConnections({ handleType: 'source' });

	const step = $derived(data.step);
	const category = $derived(data.info?.category ?? 'custom');
	const destructive = $derived(data.info?.destructive === true);
	const joinSources = $derived(incoming.current.map((c) => c.source).sort());
	const isJoin = $derived(joinSources.length >= 2);

	const parameterText = $derived(
		Object.entries(step.parameters)
			.map(([key, value]) => `${key.charAt(0).toUpperCase()}${key.slice(1)} = ${value}`)
			.join(' · ')
	);
</script>

<article
	class="node"
	class:destructive
	class:selected
	class:has-warning={findings.warnings.length > 0}
	class:has-error={findings.errors.length > 0}
	style:--node-category={`var(--category-${category})`}
	data-step-id={id}
	data-category={category}
>
	{#if destructive}
		<div class="hazard-band" data-testid="hazard-band" aria-hidden="true"></div>
	{/if}

	<div class="body">
		<header class="title-row">
			<h3 class="title">{step.taskName}</h3>
			<span class="step-id">#{id}</span>
		</header>

		<div class="chips">
			{#if destructive}
				<span class="seal" data-testid="destructive-seal">
					<svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
						<path d="M5 0.8 L9.4 8.8 L0.6 8.8 Z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" />
						<path d="M5 3.6 L5 6.2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" />
					</svg>
					DESTRUCTIVE
				</span>
			{/if}
			<span class="chip">{step.namespace || '—'}</span>
			{#if data.info?.available === false}
				<span class="chip unavailable" data-testid="unavailable-chip" title="Not supported on the target platform in v1">not in v1</span>
			{:else if !destructive}
				<span class="muted">namespace</span>
			{/if}
		</div>

		{#if step.databaseDirectory}
			<div class="muted mono">{step.databaseDirectory}</div>
		{/if}
		{#if parameterText}
			<div class="muted mono">{parameterText}{destructive ? ' · irreversible' : ''}</div>
		{/if}

		{#each findings.warnings as warning (warning.code)}
			<div class="finding warning" data-testid="precondition-warning">
				<svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
					<path d="M7 1.4 L13 12.2 L1 12.2 Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" />
					<path d="M7 5.2 L7 8.6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
					<circle cx="7" cy="10.4" r="0.8" fill="currentColor" />
				</svg>
				<div>
					<div class="finding-title">Precondition not met</div>
					<div class="finding-body">{warning.message}</div>
				</div>
			</div>
		{/each}

		{#if findings.errors.length > 0}
			<div class="finding error" data-testid="validation-error">
				<svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
					<circle cx="7" cy="7" r="5.8" fill="none" stroke="currentColor" stroke-width="1.4" />
					<path d="M7 3.8 L7 7.6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
					<circle cx="7" cy="9.9" r="0.8" fill="currentColor" />
				</svg>
				<div>
					<div class="finding-title">Blocks scheduling</div>
					{#each findings.errors as error (error.code)}
						<div class="finding-body">{error.message}</div>
					{/each}
				</div>
			</div>
		{/if}

		<div class="divider"></div>

		{#if isJoin}
			<div class="join-line">
				<span class="join-glyph" aria-hidden="true"></span>
				<span>join: waits for {joinSources.map((s) => `#${s}`).join(' ')}</span>
			</div>
		{/if}
		<footer class="footer">
			<span>{step.timeoutMinutes === null ? 'no timeout' : `timeout ${step.timeoutMinutes} min`}</span>
			<span>wqm: {step.wqmCategory || '—'}</span>
		</footer>
	</div>

	<Handle
		type="target"
		position={Position.Left}
		class={['handle', isJoin ? 'handle-join' : 'handle-plain', incoming.current.length > 0 && 'connected']}
	/>
	<Handle
		type="source"
		position={Position.Right}
		class={['handle', 'handle-plain', outgoing.current.length > 0 && 'connected']}
	/>
</article>

<style>
	.node {
		position: relative;
		box-sizing: border-box;
		width: 240px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-left: 3px solid var(--node-category);
		border-radius: var(--radius-node);
		box-shadow: var(--color-card-shadow);
		color: var(--color-text);
		font-family: var(--font-ui);
	}

	/* FR-007: the left border is always the category colour — destructive keeps it, and adds
	   the hazard band and seal on top, never replacing category with a state colour. */
	/* No overflow:hidden here — handles straddle the node edge and would be clipped, leaving
	   the output handle of a destructive step ungrabbable. The band rounds its own corners. */
	.node.destructive {
		border-color: var(--destructive-accent);
		border-left-color: var(--node-category);
	}

	.node.selected {
		border-color: var(--color-focus-ring);
		border-left-color: var(--node-category);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-focus-ring) 22%, transparent);
	}

	/* UI-007 §2 — selection is a shadow, not a glow: a 2 px solid accent border (1 px border +
	   1 px ring) over the card's 1 px drop shadow. The halo above is a dark-theme device. */
	:global([data-theme='light']) .node.selected {
		box-shadow:
			0 0 0 1px var(--color-focus-ring),
			var(--color-card-shadow);
	}

	/* FR-008: a precondition warning switches the node border to the warning token. */
	.node.has-warning {
		border-color: var(--warning-border);
		border-left-color: var(--node-category);
	}

	.node.has-error {
		border-color: var(--destructive-accent);
		border-left-color: var(--node-category);
	}

	.finding {
		display: flex;
		align-items: flex-start;
		gap: 7px;
		padding: 7px 8px;
		border-radius: var(--radius-control);
	}

	.finding svg {
		flex-shrink: 0;
		margin-top: 1px;
	}

	.finding.warning {
		color: var(--warning-accent);
		background: var(--warning-surface);
		border: 1px solid var(--warning-border);
	}

	.finding.warning .finding-title {
		color: var(--warning-title);
	}

	.finding.warning .finding-body {
		color: var(--warning-body);
	}

	.finding.error {
		color: var(--destructive-accent);
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-border);
	}

	.finding.error .finding-title {
		color: var(--destructive-text);
	}

	.finding.error .finding-body {
		color: var(--destructive-body-text);
	}

	.finding-title {
		font-size: var(--size-caption);
		font-weight: 600;
	}

	.finding-body {
		font-size: var(--size-micro);
		line-height: 1.45;
	}

	.hazard-band {
		height: var(--destructive-hazard-height);
		border-top-right-radius: calc(var(--radius-node) - 1px);
		background: repeating-linear-gradient(
			var(--destructive-hazard-angle),
			var(--destructive-accent) 0 var(--destructive-hazard-stripe),
			var(--color-card) var(--destructive-hazard-stripe) calc(var(--destructive-hazard-stripe) * 2)
		);
	}

	.body {
		display: flex;
		flex-direction: column;
		gap: var(--space-snug);
		padding: var(--space-base) 11px;
	}

	.title-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
	}

	.title {
		margin: 0;
		font-size: var(--size-bodyStrong);
		font-weight: 600;
		color: var(--color-text-strong);
	}

	.step-id,
	.mono,
	.chip,
	.seal,
	.footer {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
	}

	.step-id,
	.footer {
		color: var(--color-text-muted);
	}

	.chips {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.chip {
		color: var(--color-text);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-chip);
		padding: 1px 5px;
	}

	.chip,
	.seal {
		white-space: nowrap;
	}

	.chip.unavailable {
		color: var(--color-text-muted);
		border-style: dashed;
	}

	.seal {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-weight: 600;
		letter-spacing: 0.08em;
		color: var(--destructive-text);
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-accent);
		border-radius: var(--radius-chip);
		padding: 2px 6px;
	}

	.muted {
		color: var(--color-text-muted);
		font-size: var(--size-micro);
	}

	.divider {
		height: 1px;
		background: var(--color-border-faint);
	}

	.footer {
		display: flex;
		justify-content: space-between;
		gap: 8px;
	}

	.join-line {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: var(--size-micro);
		color: var(--color-text-muted);
	}

	.join-glyph {
		width: 8px;
		height: 8px;
		border: 1.5px solid var(--edge-join-color);
		border-radius: 1px;
		transform: rotate(45deg);
	}

	/* Handles (UI-006): plain = 8px square, 1.5px border, 2px radius; join = 10px diamond, 2px. */
	.node :global(.handle) {
		background: var(--canvas-ground);
		border-radius: var(--handle-plain-radius);
	}

	.node :global(.handle-plain) {
		width: var(--handle-plain-size);
		height: var(--handle-plain-size);
		min-width: 0;
		min-height: 0;
		border: var(--handle-plain-stroke) solid var(--color-border-strong);
	}

	.node :global(.handle-plain.connected) {
		border-color: var(--color-text-muted);
	}

	.node :global(.handle-join) {
		width: var(--handle-join-size);
		height: var(--handle-join-size);
		border: var(--handle-join-stroke) solid var(--edge-join-color);
		border-radius: 0;
		transform: translate(-50%, -50%) rotate(45deg);
	}
</style>
