<script lang="ts">
	import type { JobState } from './tokens';

	// UI-006: shape is the contract and never varies; colour is a token and may be re-valued
	// per theme. These six SVG primitives live in this one component — no screen draws its own.
	let {
		state,
		size = 14,
		label,
		class: className = ''
	}: {
		state: JobState;
		size?: number;
		/** When given, the shape is announced as this label. Omit when adjacent text already
		 *  states the job state, to avoid double-announcing it to assistive tech. */
		label?: string;
		class?: string;
	} = $props();
</script>

<svg
	class={className}
	width={size}
	height={size}
	viewBox="0 0 16 16"
	style:color={`var(--state-${state})`}
	role={label ? 'img' : undefined}
	aria-label={label}
	aria-hidden={label ? undefined : 'true'}
	focusable="false"
>
	{#if state === 'queued'}
		<rect
			x="2"
			y="2"
			width="12"
			height="12"
			rx="1.5"
			fill="none"
			stroke="currentColor"
			stroke-width="1.4"
			stroke-dasharray="2.6 2"
		/>
	{:else if state === 'running'}
		<path d="M4 2 L14 8 L4 14 Z" fill="currentColor" />
	{:else if state === 'paused'}
		<rect x="3" y="2" width="3.5" height="12" fill="currentColor" />
		<rect x="9.5" y="2" width="3.5" height="12" fill="currentColor" />
	{:else if state === 'completed'}
		<circle cx="8" cy="8" r="7" fill="currentColor" />
		<path
			d="M4.5 8.3 L7 10.8 L11.5 5.5"
			fill="none"
			stroke="var(--color-surface)"
			stroke-width="1.6"
			stroke-linecap="round"
			stroke-linejoin="round"
		/>
	{:else if state === 'failed'}
		<path d="M8 1.3 L15.2 14.5 L0.8 14.5 Z" fill="currentColor" />
		<rect x="7.15" y="6" width="1.7" height="4.2" fill="var(--color-surface)" />
		<rect x="7.15" y="11.2" width="1.7" height="1.7" fill="var(--color-surface)" />
	{:else if state === 'cancelled'}
		<circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.6" />
		<line x1="3.6" y1="12.4" x2="12.4" y2="3.6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
	{/if}
</svg>
