import { getContext, setContext } from 'svelte';
import { api, describeError, type ApiResult } from '$lib/api/client';
import { isTerminal, type RunView, type StepRunView } from './run';

// Transport: polling GET /runs/{guid}. The SSE stream works with fetch + Bearer, but the IRIS web
// gateway gzips it and the stream breaks mid-run; sse-protocol.md guarantees polling shows the
// same persisted state (plan-us4-live-run.md).
const POLL_MS = 1000;
const CLOCK_MS = 100;

export class RunMonitor {
	run = $state.raw<RunView | null>(null);
	error = $state<string | null>(null);
	notice = $state<string | null>(null);
	busy = $state(false);
	/** Ticks while the run is live, so elapsed times move between polls. */
	now = $state(Date.now());

	#pollTimer: ReturnType<typeof setTimeout> | undefined;
	#clockTimer: ReturnType<typeof setInterval> | undefined;
	#stopped = false;

	constructor(readonly guid: string) {}

	start(): void {
		this.#stopped = false;
		this.#clockTimer = setInterval(() => (this.now = Date.now()), CLOCK_MS);
		void this.#poll();
	}

	stop(): void {
		this.#stopped = true;
		clearTimeout(this.#pollTimer);
		clearInterval(this.#clockTimer);
	}

	stepFor(stepId: string): StepRunView | undefined {
		return this.run?.steps.find((s) => s.stepId === stepId);
	}

	async cancelRun(): Promise<void> {
		await this.#act(() => api.runAction(this.guid, 'cancel'));
	}

	async pauseRun(): Promise<void> {
		await this.#act(() => api.runAction(this.guid, 'pause'));
	}

	async cancelStep(stepGuid: string): Promise<void> {
		await this.#act(() => api.stepAction(this.guid, stepGuid, 'cancel'));
	}

	async rerunStep(stepGuid: string): Promise<void> {
		await this.#act(() => api.stepAction(this.guid, stepGuid, 'rerun'));
	}

	async #act(call: () => Promise<ApiResult<unknown>>): Promise<void> {
		this.busy = true;
		const result = await call();
		this.busy = false;
		// The platform's refusal (e.g. 409 on a rerun) is shown as it gave it (Constitution III).
		this.notice = result.ok ? null : describeError(result.error);
		clearTimeout(this.#pollTimer);
		await this.#poll();
	}

	async #poll(): Promise<void> {
		if (this.#stopped) return;
		const result = await api.getRun(this.guid);
		if (result.ok) {
			this.run = result.value;
			this.error = null;
		} else {
			this.error = describeError(result.error);
		}
		this.now = Date.now();
		if (this.#stopped) return;
		// Keep polling while live — and after a transport error, so a blip does not freeze the view.
		if (!this.run || !isTerminal(this.run.state) || !result.ok) {
			this.#pollTimer = setTimeout(() => void this.#poll(), POLL_MS);
		}
	}
}

const KEY = Symbol('run-monitor');
export const setRunContext = (monitor: RunMonitor): RunMonitor => setContext(KEY, monitor);
/** Undefined outside the live-run view (the editor shares edge components with it). */
export const getRunContext = (): RunMonitor | undefined => getContext<RunMonitor | undefined>(KEY);
