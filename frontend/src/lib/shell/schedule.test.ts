import { describe as suite, expect, it } from 'vitest';
import { describe, emptyForm, fieldErrors, formFrom, fromWireScheduleRead, refusalField, scheduleOf, toRequest } from './schedule';

suite('schedule form (spec 015 D-7)', () => {
	it('builds the request with one password per target the flow uses', () => {
		const form = { ...emptyForm('nightly-ops'), kind: 'weekly' as const, days: [5, 1, 5], startTime: '22:30', password: 'p' };
		form.targetPasswords = { 'iris-target': 't', unused: 'x' };
		expect(toRequest(form, ['iris-target'])).toEqual({
			schedule: { kind: 'weekly', startTime: '22:30', days: [1, 5] },
			runAs: 'nightly-ops',
			password: 'p',
			targetPasswords: [{ target: 'iris-target', password: 't' }]
		});
	});

	it('sends only the fields of the chosen kind', () => {
		const base = emptyForm('ops');
		expect(scheduleOf({ ...base, kind: 'daily' })).toEqual({ kind: 'daily', startTime: '03:00' });
		expect(scheduleOf({ ...base, kind: 'monthly', dayOfMonth: 15 })).toEqual({ kind: 'monthly', startTime: '03:00', dayOfMonth: 15 });
		expect(scheduleOf({ ...base, kind: 'hourly', everyHours: 6 })).toEqual({ kind: 'hourly', startTime: '03:00', everyHours: 6 });
	});

	it('says the schedule in the same words as the API', () => {
		expect(describe({ kind: 'daily', startTime: '03:00' })).toBe('Daily at 03:00');
		expect(describe({ kind: 'weekly', startTime: '22:30', days: [4, 1] })).toBe('Weekly on Mon, Thu at 22:30');
		expect(describe({ kind: 'monthly', startTime: '04:00', dayOfMonth: 1 })).toBe('Monthly on day 1 at 04:00');
		expect(describe({ kind: 'hourly', startTime: '00:00', everyHours: 4 })).toBe('Every 4 hours from 00:00');
		expect(describe({ kind: 'hourly', startTime: '06:00', everyHours: 1 })).toBe('Every 1 hour from 06:00');
	});

	it('reports field errors before sending', () => {
		const ok = { ...emptyForm('ops'), password: 'p', targetPasswords: { t1: 'x' } };
		expect(fieldErrors(ok, ['t1'])).toEqual({});
		expect(Object.keys(fieldErrors({ ...ok, kind: 'weekly', days: [] }, ['t1']))).toEqual(['days']);
		expect(Object.keys(fieldErrors({ ...ok, kind: 'monthly', dayOfMonth: 32 }, ['t1']))).toEqual(['dayOfMonth']);
		expect(Object.keys(fieldErrors({ ...ok, kind: 'hourly', everyHours: 13 }, ['t1']))).toEqual(['everyHours']);
		expect(Object.keys(fieldErrors({ ...ok, startTime: '24:00' }, ['t1']))).toEqual(['startTime']);
		expect(Object.keys(fieldErrors({ ...ok, password: '', runAs: ' ' }, ['t1', 't2']))).toEqual(['runAs', 'password', 'target:t2']);
	});

	it('puts a refusal on the field it is about', () => {
		expect(refusalField({ code: 'CREDENTIAL_REFUSED', instance: 'primary' })).toBe('password');
		expect(refusalField({ code: 'CREDENTIAL_REFUSED', instance: 'iris-target' })).toBe('target:iris-target');
		expect(refusalField({ code: 'SCHEDULE_INVALID', field: 'days' })).toBe('days');
		expect(refusalField({})).toBe('form');
	});

	it('reads the current schedule and fills the form without passwords', () => {
		const read = fromWireScheduleRead({
			scheduled: true,
			instanceTime: '2026-09-29 10:00:00',
			schedule: { kind: 'weekly', startTime: '03:00', days: [6] },
			describe: 'Weekly on Sat at 03:00',
			runAs: 'nightly-ops',
			targets: ['iris-target'],
			taskId: 42,
			nextRun: '2026-10-03 03:00:00',
			lastRun: null
		});
		expect(read.scheduled).toBe(true);
		if (!read.scheduled) return;
		const form = formFrom(read);
		expect(form).toMatchObject({ kind: 'weekly', days: [6], runAs: 'nightly-ops', password: '', targetPasswords: {} });
		expect(fromWireScheduleRead({ scheduled: false, instanceTime: 'x' })).toEqual({ scheduled: false, instanceTime: 'x' });
	});
});
