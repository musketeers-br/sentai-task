<script lang="ts">
	import { api, describeError } from '$lib/api/client';
	import { session } from '$lib/api/session.svelte';
	import type { FlowEditor, ScheduleOutcome } from '$lib/flow/editor.svelte';
	import { targetsUsedBy } from '$lib/targets/targets';
	import {
		DAY_NAMES,
		KINDS,
		describe,
		emptyForm,
		fieldErrors,
		formFrom,
		scheduleOf,
		toRequest,
		type ScheduleForm,
		type ScheduleRead
	} from './schedule';

	// Spec 015 (plan D-7): one native Task Manager task per flow, running as a run-as account whose
	// passwords are checked by signing in and kept only in the platform's IRIS Wallet. The passwords
	// live in this dialog's state only, and are cleared when it closes.
	let { editor, open = $bindable(false) }: { editor: FlowEditor; open: boolean } = $props();

	let dialog: HTMLDialogElement;
	let current = $state<ScheduleRead | null>(null);
	let readError = $state('');
	let form = $state<ScheduleForm>(emptyForm(''));
	let busy = $state(false);
	let outcome = $state<ScheduleOutcome | null>(null);
	let removed = $state('');
	let confirmUnschedule = $state(false);
	let shown = $state<Record<string, string>>({});

	const targets = $derived(targetsUsedBy(editor.steps));
	const scheduled = $derived(current?.scheduled === true ? current : null);

	$effect(() => {
		if (open && !dialog.open) {
			reset();
			dialog.showModal();
			void load();
		} else if (!open && dialog.open) {
			dialog.close();
		}
	});

	function reset() {
		current = null;
		readError = '';
		outcome = null;
		removed = '';
		confirmUnschedule = false;
		shown = {};
		form = emptyForm(session.user ?? '');
	}

	async function load() {
		if (!editor.id) return;
		const read = await api.getSchedule(editor.id);
		if (!read.ok) {
			readError = describeError(read.error);
			return;
		}
		current = read.value;
		if (read.value.scheduled) form = formFrom(read.value);
	}

	function onclose() {
		// Nothing typed survives the dialog (FR-003).
		form = emptyForm('');
		open = false;
	}

	async function submit(timingFromCurrent: boolean) {
		const next = timingFromCurrent && scheduled ? { ...formFrom(scheduled), runAs: form.runAs, password: form.password, targetPasswords: form.targetPasswords } : form;
		shown = fieldErrors(next, targets);
		if (Object.keys(shown).length > 0) return;
		busy = true;
		outcome = await editor.schedule(toRequest(next, targets));
		busy = false;
		if (outcome.ok) {
			form = { ...next, password: '', targetPasswords: {} };
			await load();
		} else if (outcome.field !== 'form') {
			shown = { [outcome.field]: outcome.message };
		}
	}

	async function unschedule() {
		if (!editor.id) return;
		busy = true;
		const result = await api.unschedule(editor.id);
		busy = false;
		confirmUnschedule = false;
		if (!result.ok) {
			outcome = { ok: false, message: describeError(result.error), report: null, field: 'form' };
			return;
		}
		outcome = null;
		removed =
			result.value.residue.length > 0
				? `Unscheduled, but the platform kept: ${result.value.residue.map((r) => `${r.task ? `task ${r.task}` : r.secret} (${r.detail})`).join('; ')}`
				: 'Unscheduled: the task and the stored credentials were removed.';
		await load();
		form = emptyForm(session.user ?? '');
	}

	function toggleDay(d: number) {
		form.days = form.days.includes(d) ? form.days.filter((x) => x !== d) : [...form.days, d];
	}

	function onsubmit(event: SubmitEvent) {
		event.preventDefault();
		void submit(false);
	}
</script>

<dialog bind:this={dialog} {onclose} aria-labelledby="schedule-title">
	<form {onsubmit}>
		<h2 id="schedule-title">Schedule in Task Manager</h2>
		<p class="lead">
			One IRIS Task Manager task starts <strong>{editor.name}</strong> on this schedule, as the account below.
			Destructive steps cannot be scheduled.
		</p>

		{#if readError}
			<p class="result error" role="alert">{readError}</p>
		{:else if scheduled}
			<div class="current" data-testid="schedule-current">
				<strong>{scheduled.describe}</strong> as <span class="mono">{scheduled.runAs}</span><br />
				Next run: <span class="mono" data-testid="schedule-next">{scheduled.nextRun ?? 'not reported by the platform'}</span> · task
				<span class="mono">{scheduled.taskId}</span>
				{#if scheduled.lastRun}<br />Last scheduled run: {scheduled.lastRun.state} ({scheduled.lastRun.startedAt}){/if}
			</div>
		{:else if current}
			<p class="muted" data-testid="schedule-none">Not scheduled.</p>
		{/if}
		{#if current}<p class="muted small">Times are the instance's clock: it is now <span class="mono" data-testid="schedule-instance-time">{current.instanceTime.slice(0, 16)}</span> there.</p>{/if}

		<fieldset class="when">
			<legend>When</legend>
			<div class="kinds" role="radiogroup" aria-label="Repeat">
				{#each KINDS as k (k.kind)}
					<label class="kind"><input type="radio" name="kind" value={k.kind} bind:group={form.kind} />{k.label}</label>
				{/each}
			</div>
			{#if form.kind === 'weekly'}
				<div class="days" aria-label="Days">
					{#each DAY_NAMES as name, i (name)}
						<label class="day"><input type="checkbox" checked={form.days.includes(i + 1)} onchange={() => toggleDay(i + 1)} />{name}</label>
					{/each}
				</div>
				{#if shown.days}<p class="field-error" role="alert">{shown.days}</p>{/if}
			{:else if form.kind === 'monthly'}
				<label for="schedule-dom">Day of the month</label>
				<input id="schedule-dom" type="number" min="1" max="31" bind:value={form.dayOfMonth} />
				{#if shown.dayOfMonth}<p class="field-error" role="alert">{shown.dayOfMonth}</p>{/if}
			{:else if form.kind === 'hourly'}
				<label for="schedule-every">Every (hours)</label>
				<input id="schedule-every" type="number" min="1" max="12" bind:value={form.everyHours} />
				{#if shown.everyHours}<p class="field-error" role="alert">{shown.everyHours}</p>{/if}
			{/if}
			<label for="schedule-time">{form.kind === 'hourly' ? 'Starting at' : 'At'}</label>
			<input id="schedule-time" class="mono" bind:value={form.startTime} placeholder="03:00" />
			{#if shown.startTime}<p class="field-error" role="alert">{shown.startTime}</p>{/if}
			<p class="muted small" data-testid="schedule-describe">{describe(scheduleOf(form))}</p>
		</fieldset>

		<label for="schedule-runas">Run as</label>
		<input id="schedule-runas" class="mono" bind:value={form.runAs} autocomplete="off" />
		{#if shown.runAs}<p class="field-error" role="alert">{shown.runAs}</p>{/if}
		<label for="schedule-password">Password for {form.runAs || 'that account'}</label>
		<input id="schedule-password" type="password" bind:value={form.password} autocomplete="new-password" />
		{#if shown.password}<p class="field-error" role="alert" data-testid="schedule-password-error">{shown.password}</p>{/if}
		{#each targets as target (target)}
			<label for={`schedule-target-${target}`}>Password for {form.runAs || 'that account'} on {target}</label>
			<input id={`schedule-target-${target}`} type="password" bind:value={form.targetPasswords[target]} autocomplete="new-password" />
			{#if shown[`target:${target}`]}<p class="field-error" role="alert">{shown[`target:${target}`]}</p>{/if}
		{/each}
		<p class="muted small" data-testid="schedule-wallet">
			Each password is checked by signing in, then kept only in this instance's IRIS Wallet (collection SentaiTask),
			usable only by accounts holding the SentaiSchedule resource. SentaiTask never stores or shows it.
		</p>

		{#if outcome?.ok}
			<div class="result ok" role="status" data-testid="schedule-result">
				Scheduled: {outcome.result.describe}. Task {outcome.result.taskId}, next run {outcome.result.nextRun ?? 'not reported'}.
				{#if outcome.result.residue.length > 0}
					<br />The platform kept some old items: {outcome.result.residue.map((r) => `${r.task ? `task ${r.task}` : r.secret} (${r.detail})`).join('; ')}
				{/if}
			</div>
		{:else if outcome && outcome.field === 'form'}
			<div class="result error" role="alert" data-testid="schedule-result">
				{#if outcome.report}
					<p>Not scheduled:</p>
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
		{#if removed}<div class="result ok" role="status" data-testid="schedule-removed">{removed}</div>{/if}

		{#if confirmUnschedule}
			<div class="confirm" role="alertdialog" aria-label="Unschedule">
				Remove the task and the stored credentials of this flow?
				<button type="button" class="danger" disabled={busy} onclick={unschedule}>Unschedule</button>
				<button type="button" class="quiet" onclick={() => (confirmUnschedule = false)}>Keep</button>
			</div>
		{/if}

		<div class="actions">
			{#if scheduled}
				<button type="button" class="quiet" disabled={busy} onclick={() => (confirmUnschedule = true)}>Unschedule…</button>
				<span class="spacer"></span>
				<button type="button" class="quiet" disabled={busy} onclick={() => submit(true)} title="Same timing, new passwords">Renew credential</button>
			{:else}
				<span class="spacer"></span>
			{/if}
			<button type="button" class="quiet" onclick={() => (open = false)}>Close</button>
			<button type="submit" class="primary" disabled={busy}>{busy ? 'Saving…' : scheduled ? 'Update' : 'Schedule'}</button>
		</div>
	</form>
</dialog>

<style>
	dialog {
		width: 480px;
		max-height: 92vh;
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
		gap: 6px;
		padding: 22px;
	}

	h2 {
		margin: 0;
		font-size: var(--size-sectionTitle);
		font-weight: 600;
	}

	.lead {
		margin: 0 0 4px;
		font-size: var(--size-body);
		line-height: 1.5;
		color: var(--color-text-muted);
	}

	.current {
		font-size: var(--size-body);
		line-height: 1.6;
		padding: 9px 10px;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
	}

	.muted {
		margin: 0;
		color: var(--color-text-muted);
	}

	.small {
		font-size: var(--size-caption);
		line-height: 1.5;
	}

	fieldset {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 4px 0;
		padding: 8px 10px 10px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
	}

	legend,
	label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.kinds,
	.days {
		display: flex;
		flex-wrap: wrap;
		gap: 10px;
	}

	.kind,
	.day {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		color: var(--color-text);
		font-size: var(--size-body);
	}

	input:not([type='radio']):not([type='checkbox']) {
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-ground);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 9px;
	}

	.mono {
		font-family: var(--font-mono);
	}

	.field-error {
		margin: 0;
		font-size: var(--size-caption);
		color: var(--destructive-body-text);
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

	.confirm {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 8px;
		font-size: var(--size-body);
		padding: 10px;
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-border);
		border-radius: var(--radius-control);
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-top: 8px;
	}

	.spacer {
		flex: 1;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 7px 12px;
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

	.danger {
		font-weight: 600;
		color: var(--destructive-body-text);
		background: transparent;
		border: 1px solid var(--destructive-border);
	}
</style>
