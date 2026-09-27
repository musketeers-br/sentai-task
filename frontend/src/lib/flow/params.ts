// The inspector's parameter form, generated from the API's declared schema (spec 007 D-6, FR-013…
// FR-016). Pure: no local schema, no copied default, no range or required check — the API validates
// and its findings are shown verbatim, on the field only when they name it (research R-4).
import type { ParameterSpec } from './document';
import type { Finding } from './report';

export type ParameterControl = 'text' | 'integer' | 'number' | 'checkbox' | 'readonly';

export interface ParameterField {
	name: string;
	/** The API name, capitalised as the node shows it (spec 002). */
	label: string;
	control: ParameterControl;
	required: boolean;
	/** "0–100", "≥ 0", "≤ 10", or "" — the declared bounds, shown as a hint. */
	bounds: string;
	/** "default: <value>" when the schema declares one: the backend applies it when the key is absent. */
	placeholder: string;
	help: string;
	value: string | boolean;
}

const CONTROLS: Record<string, ParameterControl> = { string: 'text', integer: 'integer', number: 'number', boolean: 'checkbox' };

function capitalise(name: string): string {
	return name.charAt(0).toUpperCase() + name.slice(1);
}

function bounds(spec: ParameterSpec): string {
	if (spec.min !== undefined && spec.max !== undefined) return `${spec.min}–${spec.max}`;
	if (spec.min !== undefined) return `≥ ${spec.min}`;
	if (spec.max !== undefined) return `≤ ${spec.max}`;
	return '';
}

export function fieldsFor(specs: ParameterSpec[], parameters: Record<string, unknown>): ParameterField[] {
	return specs.map((spec) => {
		// An unknown type is shown, never offered as free text (Constitution II).
		const control = CONTROLS[spec.type] ?? 'readonly';
		const stored = parameters[spec.name];
		return {
			name: spec.name,
			label: capitalise(spec.name),
			control,
			required: spec.required,
			bounds: control === 'readonly' ? '' : bounds(spec),
			placeholder: spec.default !== undefined && control !== 'checkbox' ? `default: ${spec.default}` : '',
			help: spec.description,
			value: control === 'checkbox' ? stored === true : stored === undefined || stored === null ? '' : String(stored)
		};
	});
}

/**
 * The step's parameters after one edit: numbers as numbers, a checkbox as a boolean, text as is; a
 * cleared field removes the key (the backend then applies the declared default, R-7). A value that
 * is not a number is sent as typed, so the API reports it — the browser checks nothing.
 */
export function writeParameter(parameters: Record<string, unknown>, spec: ParameterSpec, raw: string | boolean): Record<string, unknown> {
	const next = { ...parameters };
	if (typeof raw === 'boolean') {
		next[spec.name] = raw;
		return next;
	}
	if (raw.trim() === '') {
		delete next[spec.name];
		return next;
	}
	if (spec.type === 'integer' || spec.type === 'number') {
		const n = Number(raw);
		next[spec.name] = Number.isFinite(n) ? n : raw;
		return next;
	}
	next[spec.name] = raw;
	return next;
}

/**
 * Findings of one step, split by the structured `parameter` only (spec 005 BD-1): on the field it
 * names when the schema has it, otherwise at step level. The message is shown, never parsed.
 */
export function routeFindings(findings: Finding[], specs: ParameterSpec[]): { byField: Map<string, string[]>; stepLevel: string[] } {
	const names = new Set(specs.map((s) => s.name));
	const byField = new Map<string, string[]>();
	const stepLevel: string[] = [];
	for (const finding of findings) {
		const target = finding.parameter !== undefined && names.has(finding.parameter) ? finding.parameter : null;
		const message = finding.message;
		if (target === null) stepLevel.push(message);
		else byField.set(target, [...(byField.get(target) ?? []), message]);
	}
	return { byField, stepLevel };
}
