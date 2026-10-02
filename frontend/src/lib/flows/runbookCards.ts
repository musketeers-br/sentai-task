// Spec 022 US3 (FR-005, FR-007; data-model §2): the pure card view model. A card's verdict is
// derived from catalog and target data — a step type not declared or not available, a remote
// step's target server not registered — and nothing else. It is never a permission decision:
// the platform decides permission at create and run time, and its refusal surfaces verbatim
// (Constitution III, FR-009). Pure — no Svelte, no I/O.
import type { StepTypeInfo } from '$lib/flow/document';
import { stepLabel, typeLabel } from '$lib/flow/document';
import type { Runbook } from './runbooks';

export type Availability =
	| { kind: 'runnable' }
	/** Names the missing thing — the reason the card states (FR-007). */
	| { kind: 'unavailable'; reason: string };

export interface RunbookCard {
	runbook: Runbook;
	steps: Array<{ id: string; label: string; destructive: boolean; onTarget: string | null }>;
	cadence: string | undefined;
	availability: Availability;
}

/**
 * One card per runbook. `targets` are the registered target names (what GET /targets returned
 * for this instance); the page refetches them per gallery show — nothing is cached across
 * requests (Constitution III).
 */
export function runbookCards(
	runbooks: readonly Runbook[],
	registry: readonly StepTypeInfo[],
	targets: readonly string[]
): RunbookCard[] {
	return runbooks.map((runbook) => {
		const steps = runbook.definition.steps.map((step) => {
			const info = registry.find((r) => r.type === step.type);
			return {
				id: step.id,
				label: info ? typeLabel(info) : step.type,
				destructive: info?.destructive ?? false,
				onTarget: step.target ?? null
			};
		});

		const unavailableStep = runbook.definition.steps.find((step) => {
			const info = registry.find((r) => r.type === step.type);
			return info === undefined || !info.available;
		});
		if (unavailableStep) {
			const info = registry.find((r) => r.type === unavailableStep.type);
			return {
				runbook,
				steps,
				cadence: runbook.suggestedCadence,
				availability: {
					kind: 'unavailable',
					reason: `${info ? typeLabel(info) : stepLabel(unavailableStep.type)} is not available on this instance.`
				}
			};
		}

		const remoteStep = runbook.definition.steps.find((step) => step.target !== undefined && !targets.includes(step.target));
		if (remoteStep) {
			return {
				runbook,
				steps,
				cadence: runbook.suggestedCadence,
				availability: {
					kind: 'unavailable',
					reason: `The ${remoteStep.target} target server is not registered.`
				}
			};
		}

		return { runbook, steps, cadence: runbook.suggestedCadence, availability: { kind: 'runnable' } };
	});
}
