// Spec 016 US2: one step's execution account — the view model the rail's STEP DETAIL renders
// (plan D-3). Facts come from the run read (StepRunView: the latest attempt) and the run's log;
// a step that has not started shows what is known and invents nothing (FR-011).
import { sliceFor } from './log';
import { stepDurationMs, type LogEntry, type StepRunView, type StepState } from './run';

export interface StepDetailView {
	stepId: string;
	/** The flow's step name; `#<id>` when the flow has none. */
	taskName: string;
	state: StepState;
	timeQueued: string | null;
	timeStarted: string | null;
	timeFinished: string | null;
	durationMs: number | null;
	/** Where it ran and as whom — null while the step has not started (FR-011). */
	executedOn: string | null;
	executedAs: string | null;
	/** The platform's own text, verbatim and whole (Constitution III). */
	failureReason: string | null;
	/** The stored result, exactly as the run read carries it (a failed step can have one). */
	result: unknown;
	/** That step's log entries — every attempt, chronological (FR-010). */
	logSlice: LogEntry[];
}

export function buildStepDetail(
	step: StepRunView,
	taskName: string | undefined,
	log: readonly LogEntry[],
	nowMs: number
): StepDetailView {
	const started = step.timeStarted !== null;
	return {
		stepId: step.stepId,
		taskName: taskName ?? `#${step.stepId}`,
		state: step.state,
		timeQueued: step.timeQueued,
		timeStarted: step.timeStarted,
		timeFinished: step.timeFinished,
		durationMs: stepDurationMs(step, nowMs),
		// The wire normalizes an empty place to "local" (Dispatcher.ShapeStepRun); a step that
		// never ran has no place or identity to show (FR-011).
		executedOn: started ? step.executedOn : null,
		executedAs: started && step.executedAs !== '' ? step.executedAs : null,
		failureReason: step.failureReason,
		result: step.result,
		logSlice: sliceFor(log, step.stepId)
	};
}

/** The result's copyable form: the stored JSON exactly, pretty-printed (SC-002). */
export function resultCopyText(result: unknown): string {
	return JSON.stringify(result ?? {}, null, 2);
}
