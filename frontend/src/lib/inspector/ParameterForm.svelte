<script lang="ts">
	import type { ParameterSpec } from '$lib/flow/document';
	import { fieldsFor, routeFindings, writeParameter } from '$lib/flow/params';
	import type { Finding } from '$lib/flow/report';

	// A form generated from the API's declared schema (spec 007 T008): one field per declared
	// parameter, nothing local. Findings appear on the field they name, else above the fields,
	// verbatim; the API validates everything (FR-015).
	let {
		specs,
		parameters,
		findings,
		onchange
	}: {
		specs: ParameterSpec[];
		parameters: Record<string, unknown>;
		findings: Finding[];
		onchange: (parameters: Record<string, unknown>) => void;
	} = $props();

	const fields = $derived(fieldsFor(specs, parameters));
	const routed = $derived(routeFindings(findings, specs));
	const specOf = (name: string) => specs.find((s) => s.name === name)!;
</script>

{#if specs.length === 0}
	<p class="none" data-testid="no-parameters">This step type takes no parameters.</p>
{:else}
	{#if routed.stepLevel.length > 0}
		<ul class="step-findings" data-testid="param-step-findings">
			{#each routed.stepLevel as message, i (i)}<li>{message}</li>{/each}
		</ul>
	{/if}
	{#each fields as field (field.name)}
		{@const errors = routed.byField.get(field.name) ?? []}
		<div class="param" class:has-error={errors.length > 0} data-testid="param-field">
			<div class="param-head">
				<label for={`insp-param-${field.name}`}>{field.label}</label>
				{#if field.required}<span class="required">required</span>{/if}
				{#if field.bounds}<span class="bounds">{field.bounds}</span>{/if}
			</div>
			{#if field.control === 'checkbox'}
				<input
					id={`insp-param-${field.name}`}
					type="checkbox"
					checked={field.value === true}
					onchange={(e) => onchange(writeParameter(parameters, specOf(field.name), e.currentTarget.checked))}
				/>
			{:else if field.control === 'readonly'}
				<span id={`insp-param-${field.name}`} class="readonly mono">{field.value === '' ? '—' : field.value} (unsupported parameter type)</span>
			{:else}
				<input
					id={`insp-param-${field.name}`}
					class="mono"
					type={field.control === 'text' ? 'text' : 'number'}
					step={field.control === 'integer' ? '1' : 'any'}
					placeholder={field.placeholder}
					value={field.value}
					aria-invalid={errors.length > 0 ? 'true' : undefined}
					aria-describedby={field.help ? `insp-param-${field.name}-help` : undefined}
					oninput={(e) => onchange(writeParameter(parameters, specOf(field.name), e.currentTarget.value))}
				/>
			{/if}
			{#if field.help}<p class="help" id={`insp-param-${field.name}-help`}>{field.help}</p>{/if}
			{#each errors as message, i (i)}
				<p class="error" data-testid={`param-error-${field.name}`}>{message}</p>
			{/each}
		</div>
	{/each}
{/if}

<style>
	.none,
	.help {
		margin: 0;
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.param {
		display: flex;
		flex-direction: column;
		gap: 4px;
		margin-bottom: 10px;
	}

	.param-head {
		display: flex;
		align-items: baseline;
		gap: 8px;
	}

	label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.required,
	.bounds {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		color: var(--color-text-muted);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-chip);
		padding: 0 5px;
	}

	input:not([type='checkbox']) {
		font: inherit;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-ground);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 6px 8px;
	}

	.has-error input {
		border-color: var(--destructive-accent);
	}

	.mono {
		font-family: var(--font-mono);
	}

	.readonly {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.error,
	.step-findings {
		margin: 0;
		font-size: var(--size-caption);
		color: var(--destructive-text);
	}

	.step-findings {
		padding-left: 16px;
		margin-bottom: 8px;
	}
</style>
