// Spec 011 US5: whether cancelling now makes IRIS raise an alert. Cancelling a running platform
// job ends its Work Queue Manager worker, which IRIS 2026.2 logs at severity 2 (the instance then
// reports "unhealthy"); in-process steps are not ended by a cancel and queued steps have no job
// yet (docs/limitations.md, spec 011 research R-8). Local and remote steps alike: a target
// records its own alert.
import type { FlowStep, StepTypeInfo } from '$lib/flow/document';
import type { StepRunView } from './run';

type RunStep = Pick<StepRunView, 'stepId' | 'state'>;
type Step = Pick<FlowStep, 'id' | 'type'>;
type TypeInfo = Pick<StepTypeInfo, 'type' | 'executor'>;

/** True when `stepRun` is running a job of a type executed through the management API. */
export function stepCancelRaisesAlert(
	stepRun: RunStep | undefined,
	flowSteps: readonly Step[],
	registry: readonly TypeInfo[]
): boolean {
	if (stepRun?.state !== 'running') return false;
	const type = flowSteps.find((s) => s.id === stepRun.stepId)?.type;
	return registry.find((t) => t.type === type)?.executor === 'platform-api';
}

/** True when cancelling the whole run would end at least one running platform job. */
export function cancelRaisesAlert(
	steps: readonly RunStep[],
	flowSteps: readonly Step[],
	registry: readonly TypeInfo[]
): boolean {
	return steps.some((s) => stepCancelRaisesAlert(s, flowSteps, registry));
}
