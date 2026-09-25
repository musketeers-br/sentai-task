<script lang="ts">
	import type { FlowEditor, ScheduleOutcome } from '$lib/flow/editor.svelte';

	let { editor, open = $bindable(false) }: { editor: FlowEditor; open: boolean } = $props();

	let dialog: HTMLDialogElement;
	let scheduleSpec = $state('WEEKLY SAT 03:00');
	let category = $state('');
	let busy = $state(false);
	let outcome = $state<ScheduleOutcome | null>(null);

	$effect(() => {
		if (open && !dialog.open) {
			outcome = null;
			category = editor.defaultCategory;
			dialog.showModal();
		} else if (!open && dialog.open) {
			dialog.close();
		}
	});

	async function onsubmit(event: SubmitEvent) {
		event.preventDefault();
		busy = true;
		outcome = await editor.schedule(scheduleSpec.trim(), category.trim());
		busy = false;
	}
</script>

<dialog bind:this={dialog} onclose={() => (open = false)} aria-labelledby="schedule-title">
	<form {onsubmit}>
		<h2 id="schedule-title">Schedule in Task Manager</h2>
		<p class="lead">
			Compiles each step of <strong>{editor.name}</strong> into a native IRIS Task Manager entry. No
			private scheduler runs anywhere.
		</p>

		<label for="schedule-spec">Schedule</label>
		<input id="schedule-spec" class="mono" required bind:value={scheduleSpec} placeholder="WEEKLY SAT 03:00" />

		<label for="schedule-category">WQM category</label>
		<input id="schedule-category" class="mono" list="wqm-categories" bind:value={category} />

		{#if outcome?.ok}
			<div class="result ok" role="status" data-testid="schedule-result">
				Created {outcome.result.taskIds.length} Task Manager entries (ids {outcome.result.taskIds.join(', ')}).
				Next run reported by the platform: {outcome.result.nextRun}.
			</div>
		{:else if outcome}
			<div class="result error" role="alert" data-testid="schedule-result">
				{#if outcome.report}
					<p>Not scheduled — the platform refused it:</p>
					<ul>
						{#each outcome.report.errors as finding (finding.code + finding.stepId)}
							<li>{finding.stepId ? `#${finding.stepId} · ` : ''}{finding.message}</li>
						{/each}
					</ul>
				{:else}
					{outcome.message}
				{/if}
			</div>
		{/if}

		<div class="actions">
			<button type="button" class="quiet" onclick={() => (open = false)}>{outcome?.ok ? 'Close' : 'Cancel'}</button>
			{#if !outcome?.ok}
				<button type="submit" class="primary" disabled={busy}>{busy ? 'Scheduling…' : 'Schedule'}</button>
			{/if}
		</div>
	</form>
</dialog>

<style>
	dialog {
		width: 440px;
		padding: 0;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-panel);
		box-shadow: 0 12px 40px rgba(0, 0, 0, 0.35);
	}

	dialog::backdrop {
		background: color-mix(in srgb, var(--color-ground) 70%, transparent);
	}

	form {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 22px;
	}

	h2 {
		margin: 0;
		font-size: var(--size-sectionTitle);
		font-weight: 600;
	}

	.lead {
		margin: 0 0 8px;
		font-size: var(--size-body);
		line-height: 1.5;
		color: var(--color-text-muted);
	}

	label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	input {
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-ground);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 8px 9px;
		margin-bottom: 6px;
	}

	.mono {
		font-family: var(--font-mono);
	}

	.result {
		font-size: var(--size-body);
		line-height: 1.5;
		padding: 10px;
		border-radius: var(--radius-control);
	}

	.result p,
	.result ul {
		margin: 0;
	}

	.result ul {
		padding-left: 18px;
	}

	.result.ok {
		color: var(--state-text-completed);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
	}

	.result.error {
		color: var(--destructive-body-text);
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-border);
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
		margin-top: 8px;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 7px 14px;
		cursor: pointer;
	}

	.primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
	}

	.quiet {
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
	}
</style>
