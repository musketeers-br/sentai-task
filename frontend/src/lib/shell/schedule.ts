// Spec 015 (plan D-7): the schedule dialog's pure logic — the form, the request it sends, the
// schedule in words, and the field errors shown before anything is sent. The passwords live only in
// the form (the dialog's local state) and are cleared when it closes.

export type ScheduleKind = 'daily' | 'weekly' | 'monthly' | 'hourly';

export interface Schedule {
	kind: ScheduleKind;
	startTime: string;
	/** Weekly: 1 = Monday … 7 = Sunday. */
	days?: number[];
	dayOfMonth?: number;
	everyHours?: number;
}

export interface ScheduleForm {
	kind: ScheduleKind;
	startTime: string;
	days: number[];
	dayOfMonth: number;
	everyHours: number;
	runAs: string;
	password: string;
	targetPasswords: Record<string, string>;
}

export interface ScheduleRequest {
	schedule: Schedule;
	runAs: string;
	password: string;
	targetPasswords: Array<{ target: string; password: string }>;
}

/** GET /flows/{id}/schedule. */
export type ScheduleRead =
	| { scheduled: false; instanceTime: string }
	| {
			scheduled: true;
			instanceTime: string;
			schedule: Schedule;
			describe: string;
			runAs: string;
			targets: string[];
			taskId: number;
			nextRun: string | null;
			lastRun: { guid: string; state: string; startedAt: string } | null;
	  };

export const KINDS: Array<{ kind: ScheduleKind; label: string }> = [
	{ kind: 'daily', label: 'Daily' },
	{ kind: 'weekly', label: 'Weekly' },
	{ kind: 'monthly', label: 'Monthly' },
	{ kind: 'hourly', label: 'Every few hours' }
];

export const DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export function emptyForm(runAs: string): ScheduleForm {
	return { kind: 'daily', startTime: '03:00', days: [6], dayOfMonth: 1, everyHours: 4, runAs, password: '', targetPasswords: {} };
}

/** The form for an existing schedule (passwords empty: they are never read back). */
export function formFrom(read: Extract<ScheduleRead, { scheduled: true }>): ScheduleForm {
	const s = read.schedule;
	return {
		kind: s.kind,
		startTime: s.startTime,
		days: s.days ?? [6],
		dayOfMonth: s.dayOfMonth ?? 1,
		everyHours: s.everyHours ?? 4,
		runAs: read.runAs,
		password: '',
		targetPasswords: {}
	};
}

export function scheduleOf(form: Pick<ScheduleForm, 'kind' | 'startTime' | 'days' | 'dayOfMonth' | 'everyHours'>): Schedule {
	const s: Schedule = { kind: form.kind, startTime: form.startTime };
	if (form.kind === 'weekly') s.days = [...new Set(form.days)].sort((a, b) => a - b);
	if (form.kind === 'monthly') s.dayOfMonth = form.dayOfMonth;
	if (form.kind === 'hourly') s.everyHours = form.everyHours;
	return s;
}

/** The request body: one password per target the flow uses, in `targets` order. */
export function toRequest(form: ScheduleForm, targets: string[]): ScheduleRequest {
	return {
		schedule: scheduleOf(form),
		runAs: form.runAs.trim(),
		password: form.password,
		targetPasswords: targets.map((target) => ({ target, password: form.targetPasswords[target] ?? '' }))
	};
}

/** The same words as the API's `describe` (sentai.schedule.Timing.Describe). */
export function describe(s: Schedule): string {
	switch (s.kind) {
		case 'daily':
			return `Daily at ${s.startTime}`;
		case 'monthly':
			return `Monthly on day ${s.dayOfMonth} at ${s.startTime}`;
		case 'hourly':
			return `Every ${s.everyHours} hour${s.everyHours === 1 ? '' : 's'} from ${s.startTime}`;
		case 'weekly': {
			const days = [...new Set(s.days ?? [])].sort((a, b) => a - b).map((d) => DAY_NAMES[d - 1]);
			return `Weekly on ${days.join(', ')} at ${s.startTime}`;
		}
	}
}

/** Field → message, checked before sending (the API checks again and has the last word). */
export function fieldErrors(form: ScheduleForm, targets: string[]): Record<string, string> {
	const errors: Record<string, string> = {};
	const m = /^(\d{2}):(\d{2})$/.exec(form.startTime);
	if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) errors.startTime = 'Use HH:MM, 00:00 to 23:59.';
	if (form.kind === 'weekly' && form.days.length === 0) errors.days = 'Choose at least one day.';
	if (form.kind === 'monthly' && !(Number.isInteger(form.dayOfMonth) && form.dayOfMonth >= 1 && form.dayOfMonth <= 31)) {
		errors.dayOfMonth = 'Day 1 to 31.';
	}
	if (form.kind === 'hourly' && !(Number.isInteger(form.everyHours) && form.everyHours >= 1 && form.everyHours <= 12)) {
		errors.everyHours = '1 to 12 hours.';
	}
	if (!form.runAs.trim()) errors.runAs = 'The account the runs act as.';
	if (!form.password) errors.password = 'The password of that account on this instance.';
	for (const t of targets) if (!form.targetPasswords[t]) errors[`target:${t}`] = `The password of that account on ${t}.`;
	return errors;
}

/**
 * Where a refusal belongs in the form: a wrong password on its own field (the API names the
 * instance: `primary` or a target), a schedule field error on that field, anything else on the form.
 */
export function refusalField(problem: { code?: string; field?: string; instance?: string }): string {
	if (problem.code === 'CREDENTIAL_REFUSED') return problem.instance && problem.instance !== 'primary' ? `target:${problem.instance}` : 'password';
	if (problem.code === 'SCHEDULE_INVALID' && problem.field) return problem.field;
	return 'form';
}

export function fromWireScheduleRead(w: Record<string, unknown>): ScheduleRead {
	const instanceTime = String(w.instanceTime ?? '');
	if (w.scheduled !== true) return { scheduled: false, instanceTime };
	const last = w.lastRun as Record<string, unknown> | null | undefined;
	return {
		scheduled: true,
		instanceTime,
		schedule: w.schedule as Schedule,
		describe: String(w.describe ?? ''),
		runAs: String(w.runAs ?? ''),
		targets: Array.isArray(w.targets) ? (w.targets as unknown[]).map(String) : [],
		taskId: Number(w.taskId),
		nextRun: w.nextRun ? String(w.nextRun) : null,
		lastRun: last ? { guid: String(last.guid), state: String(last.state), startedAt: String(last.startedAt ?? '') } : null
	};
}
