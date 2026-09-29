// Spec 012 US3 (plan D-10): a run as a file — exactly what the run view shows, nothing from the
// session (FR-014).
import { chronological } from './log';
import { isTerminal, type RunView } from './run';

export interface RunExport {
	format: 'sentai-run-export/1';
	exportedAt: string;
	exportedWhile?: 'running';
	flow: { id: string; name: string; revision: number };
	run: { guid: string; state: string; startedAt: string | null; finishedAt: string | null; dispatchedBy: string };
	steps: Array<{
		stepId: string;
		guid: string;
		state: string;
		timeQueued: string | null;
		timeStarted: string | null;
		timeFinished: string | null;
		executedOn: string;
		executedAs: string;
		failureReason: string | null;
		result: unknown;
	}>;
	log: RunView['log'];
}

export function buildRunExport(run: RunView, flowName: string, now: Date): RunExport {
	return {
		format: 'sentai-run-export/1',
		exportedAt: now.toISOString(),
		...(isTerminal(run.state) ? {} : { exportedWhile: 'running' as const }),
		flow: { id: run.flowId, name: flowName, revision: run.flowRevision },
		run: { guid: run.guid, state: run.state, startedAt: run.startedAt, finishedAt: run.finishedAt, dispatchedBy: run.dispatchedBy },
		steps: run.steps.map((s) => ({
			stepId: s.stepId,
			guid: s.guid,
			state: s.state,
			timeQueued: s.timeQueued,
			timeStarted: s.timeStarted,
			timeFinished: s.timeFinished,
			executedOn: s.executedOn,
			executedAs: s.executedAs,
			failureReason: s.failureReason,
			result: s.result
		})),
		log: chronological(run.log)
	};
}

/** `<flow-name>-<first 8 of the guid>.json`, safe on every file system. */
export function exportFileName(flowName: string, guid: string): string {
	const slug = flowName.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'run';
	return `${slug}-${guid.slice(0, 8)}.json`;
}
