<script lang="ts">
	import type { FlowEditor } from '$lib/flow/editor.svelte';
	import { targetChoices } from '$lib/targets/targets';
	import ParameterForm from './ParameterForm.svelte';

	let { editor }: { editor: FlowEditor } = $props();

	// Only for a pre-005 catalog, which declares no parameter schema: the spec 002 field. With a
	// declared schema the form is generated from the API (spec 007 T008).
	const PARAMETER_FIELDS: Record<string, Array<{ key: string; label: string }>> = {
		'purge-audit-records': [{ key: 'daysToKeep', label: 'DaysToKeep' }]
	};

	const node = $derived(editor.selectedNode);
	const step = $derived(node?.data.step);
	const info = $derived(node?.data.info);
	const parameterFields = $derived(step && info?.parameters === undefined ? (PARAMETER_FIELDS[step.type] ?? []) : []);
	const stepFindings = $derived.by(() => {
		if (!node) return [];
		const f = editor.findingsFor(node.id);
		return [...f.errors, ...f.warnings];
	});
	const selectedCount = $derived(editor.nodes.filter((n) => n.selected).length);
	/** Spec 009 FR-006: online targets, for a type the API marks remote-capable. */
	const choices = $derived(targetChoices(editor.targets, info));
	/** A stored target that is no longer offered (offline or deleted) is still shown, marked. */
	const storedElsewhere = $derived(!!step?.target && !choices.some((t) => t.name === step?.target));

	function setTarget(name: string) {
		if (node) editor.updateStep(node.id, { target: name === '' ? undefined : name });
	}

	function consequence(type: string, parameters: Record<string, unknown>): string {
		const noRollback = 'There is no rollback: it requires a valid backup taken today.';
		if (type === 'purge-audit-records') {
			return `Permanently removes audit records older than ${parameters.daysToKeep ?? '?'} days. ${noRollback}`;
		}
		if (type === 'purge-task-history') return `Permanently removes task history records. ${noRollback}`;
		return `Permanently changes data on the instance. ${noRollback}`;
	}

	function integerOrNull(value: string): number | null {
		const n = Number.parseInt(value, 10);
		return Number.isFinite(n) && n > 0 ? n : null;
	}

	function setText(field: 'taskName' | 'namespace' | 'runAsUser' | 'wqmCategory', value: string) {
		if (node) editor.updateStep(node.id, { [field]: value });
	}

	function setParameter(key: string, value: string) {
		if (!node || !step) return;
		const parameters = { ...step.parameters };
		const n = integerOrNull(value);
		// An empty or invalid value is removed, so the validator reports it instead of us guessing.
		if (n === null) delete parameters[key];
		else parameters[key] = n;
		editor.updateStep(node.id, { parameters });
	}
</script>

<aside class="inspector" aria-label="Inspector">
	<section class="head">
		<h2 class="label display">SELECTED STEP</h2>
		{#if step}
			<div class="step-title">{step.taskName}</div>
			<div class="mono faint">{info?.className || step.customClass || 'subclass of %SYS.Task.Definition'}</div>
		{:else}
			<p class="empty">
				{selectedCount > 1
					? `${selectedCount} steps selected — select one to edit it.`
					: 'Select a step on the canvas to edit it.'}
			</p>
		{/if}
	</section>

	{#if node && step}
		<div class="sections">
			<section>
				<h2 class="label">IDENTIFICATION</h2>
				<div class="field">
					<label for="insp-taskname">TaskName</label>
					<input id="insp-taskname" value={step.taskName} oninput={(e) => setText('taskName', e.currentTarget.value)} />
				</div>
				<div class="grid">
					<div class="field">
						<label for="insp-namespace">Namespace</label>
						<input id="insp-namespace" class="mono" value={step.namespace} oninput={(e) => setText('namespace', e.currentTarget.value)} />
					</div>
					<div class="field">
						<label for="insp-runas">Run as user</label>
						<input id="insp-runas" class="mono" value={step.runAsUser} oninput={(e) => setText('runAsUser', e.currentTarget.value)} />
					</div>
				</div>
				{#if info?.remoteCapable}
					<div class="field">
						<label for="insp-runon">Run on</label>
						<select id="insp-runon" class="mono" value={step.target ?? ''} onchange={(e) => setTarget(e.currentTarget.value)}>
							<option value="">Local (this instance)</option>
							{#each choices as target (target.name)}
								<option value={target.name}>{target.name}</option>
							{/each}
							{#if storedElsewhere}
								<option value={step.target}>{step.target} (offline or not registered)</option>
							{/if}
						</select>
					</div>
				{:else}
					<p class="local-note" data-testid="runs-locally-note">This step type runs on this instance only (it cannot run on a target server).</p>
				{/if}
			</section>

			<section>
				<h2 class="label">PARAMETERS</h2>
				{#if step.type === 'custom'}
					<!-- Spec 007 FR-018: a legacy custom step is shown, never edited: no field names a class. -->
					<div class="field">
						<span class="field-label">Custom class</span>
						<span class="readonly mono" data-testid="custom-class-readonly">{step.customClass || '—'}</span>
						<p class="local-note">Legacy custom steps are not supported: the class cannot be changed, and validation refuses the step.</p>
					</div>
				{:else if info?.parameters !== undefined}
					<ParameterForm
						specs={info.parameters}
						parameters={step.parameters}
						findings={stepFindings}
						onchange={(parameters) => node && editor.updateStep(node.id, { parameters })}
					/>
				{/if}
				{#each parameterFields as field (field.key)}
					<div class="row">
						<label for={`insp-param-${field.key}`}>{field.label}</label>
						<input
							id={`insp-param-${field.key}`}
							class="mono narrow"
							type="number"
							min="1"
							value={step.parameters[field.key] ?? ''}
							oninput={(e) => setParameter(field.key, e.currentTarget.value)}
						/>
					</div>
				{/each}
				<div class="row">
					<label for="insp-timeout">Timeout (min)</label>
					<input
						id="insp-timeout"
						class="mono narrow"
						type="number"
						min="1"
						placeholder="none"
						value={step.timeoutMinutes ?? ''}
						oninput={(e) => node && editor.updateStep(node.id, { timeoutMinutes: integerOrNull(e.currentTarget.value) })}
					/>
				</div>
				<div class="row">
					<label for="insp-wqm">WQM category</label>
					<input
						id="insp-wqm"
						class="mono wide"
						list="wqm-categories"
						value={step.wqmCategory}
						oninput={(e) => setText('wqmCategory', e.currentTarget.value)}
					/>
				</div>
			</section>

			{#if info?.destructive}
				<section class="destructive" aria-labelledby="insp-destructive-title">
					<h2 class="destructive-title" id="insp-destructive-title">
						<svg width="13" height="13" viewBox="0 0 14 14" aria-hidden="true">
							<path d="M7 1.4 L13 12.2 L1 12.2 Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" />
							<path d="M7 5.2 L7 8.6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
							<circle cx="7" cy="10.4" r="0.8" fill="currentColor" />
						</svg>
						DESTRUCTIVE STEP
					</h2>
					<p class="consequence">{consequence(step.type, step.parameters)}</p>
					<div class="confirm">
						<input id="insp-confirm" type="checkbox" checked disabled aria-describedby="insp-confirm-note" />
						<label for="insp-confirm">Require the database name to be typed before running</label>
					</div>
					<p class="note" id="insp-confirm-note">Always on for destructive steps — dispatch refuses them without it.</p>
				</section>
			{/if}

			<section>
				<h2 class="label">OUTPUT</h2>
				<div class="output">
					<div class="muted">GUID returned on dispatch</div>
					<code data-testid="guid-destination">step{step.id}.guid → ^sentaiRun(runGuid,"{step.id}")</code>
				</div>
			</section>
		</div>
	{/if}
</aside>

<style>
	.inspector {
		display: flex;
		flex-direction: column;
		width: var(--chrome-inspector-width);
		flex-shrink: 0;
		box-sizing: border-box;
		background: var(--color-ground-rail);
		border-left: 1px solid var(--color-border-faint);
		min-height: 0;
		overflow-y: auto;
	}

	.head {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 13px var(--space-loose);
		border-bottom: 1px solid var(--color-border-faint);
	}

	.sections {
		display: flex;
		flex-direction: column;
		gap: var(--space-loose);
		padding: var(--space-loose);
	}

	.sections > section:not(.destructive) + section {
		border-top: 1px solid var(--color-border-faint);
		padding-top: var(--space-loose);
	}

	section {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	h2 {
		margin: 0;
	}

	.label {
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.1em;
		color: var(--color-text-muted);
	}

	.label.display {
		font-family: var(--font-display);
		font-size: var(--size-caption);
		letter-spacing: 0.12em;
	}

	.step-title {
		font-size: var(--size-title);
		font-weight: 600;
		color: var(--color-text-strong);
	}

	.mono {
		font-family: var(--font-mono);
	}

	.faint {
		font-size: var(--size-micro);
		color: var(--color-text-muted);
	}

	.muted {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.empty {
		margin: 4px 0 0;
		font-size: var(--size-body);
		color: var(--color-text-muted);
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 8px;
	}

	.row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
	}

	label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.row label {
		font-size: var(--size-body);
		color: var(--color-text);
	}

	input:not([type='checkbox']) {
		box-sizing: border-box;
		width: 100%;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 9px;
	}

	input:not(.mono) {
		font-family: var(--font-ui);
	}

	.narrow {
		width: 84px;
		text-align: right;
	}

	.row input.narrow,
	.row input.wide {
		width: 84px;
		flex-shrink: 0;
	}

	.row input.wide {
		width: 132px;
		text-align: right;
	}

	.destructive {
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-border);
		border-radius: var(--radius-control);
		padding: 11px;
		gap: 9px;
	}

	.destructive-title {
		display: flex;
		align-items: center;
		gap: 7px;
		font-size: var(--size-caption);
		font-weight: 700;
		letter-spacing: 0.08em;
		color: var(--destructive-text);
	}

	.consequence,
	.note {
		margin: 0;
		font-size: var(--size-caption);
		line-height: 1.5;
		color: var(--destructive-body-text);
	}

	.note {
		font-size: var(--size-micro);
	}

	.confirm {
		display: flex;
		align-items: flex-start;
		gap: 8px;
	}

	.confirm input {
		margin: 2px 0 0;
		accent-color: var(--destructive-accent);
	}

	.confirm label {
		font-size: var(--size-caption);
		line-height: 1.45;
		color: var(--color-text);
	}

	.output {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 9px;
		background: var(--color-card);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
	}

	code {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text);
		word-break: break-all;
	}

	.field-label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.readonly {
		font-size: var(--size-body);
		padding: 6px 0;
	}

	/* Notes outside the destructive block: muted, never the destructive colour. */
	.local-note {
		margin: 6px 0 0;
		font-size: var(--size-caption);
		line-height: 1.5;
		color: var(--color-text-muted);
	}
</style>
