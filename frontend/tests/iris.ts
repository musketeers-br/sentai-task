/// <reference types="node" />
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';

// Test setup that has no product endpoint, done in the dev container's IRIS session:
// - temporary operators for refusal tests (spec 007 tasks.md, "Credentials"). The password is
//   generated here, handed to IRIS on stdin only, and never logged; the user and its role are
//   deleted by the caller in `finally`;
// - deleting a flow (the product API has no DELETE /flows/{id}).
const CONTAINER = process.env.SENTAI_CONTAINER ?? 'sentai-task-iris-1';
const NO_TASK_ROLE = 'SentaiE2ENoTask';

export interface Operator {
	user: string;
	password: string;
}

function irisSys(script: string, namespace = '%SYS'): string {
	return execFileSync('docker', ['exec', '-i', CONTAINER, 'iris', 'session', 'iris', '-U', namespace], {
		input: `${script}\nhalt\n`,
		encoding: 'utf8',
		env: { ...process.env, MSYS_NO_PATHCONV: '1' }
	});
}

/**
 * A user who can sign in and call the product API but holds no task privilege (spec 006
 * quickstart recipe: `%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW`, nothing else).
 */
export function createOperatorWithoutTaskPrivilege(): Operator {
	const user = `e2e_notask_${randomBytes(3).toString('hex')}`;
	const password = randomBytes(18).toString('base64url');
	const out = irisSys(
		[
			`if '##class(Security.Roles).Exists("${NO_TASK_ROLE}") { set sc=##class(Security.Roles).Create("${NO_TASK_ROLE}","e2e: product access without task privilege","%DB_IRISAPP_CODE:R,%DB_IRISAPP_DATA:RW") }`,
			`set sc=##class(Security.Users).Create("${user}","${NO_TASK_ROLE}","${password}","e2e temporary operator")`,
			`write "RESULT:",$select(sc=1:"OK",1:$system.Status.GetErrorText(sc)),!`
		].join('\n')
	);
	const result = /RESULT:(.*)/.exec(out)?.[1]?.trim();
	if (result !== 'OK') throw new Error(`could not create the temporary operator: ${result ?? 'no answer'}`);
	return { user, password };
}

export function deleteOperator(operator: Operator): void {
	irisSys(
		[
			`set sc=##class(Security.Users).Delete("${operator.user}")`,
			`if ##class(Security.Roles).Exists("${NO_TASK_ROLE}") { set sc=##class(Security.Roles).Delete("${NO_TASK_ROLE}") }`
		].join('\n')
	);
}

/** Deletes a flow the way no product call can, so its tasks' origin reads `flowExists: false`. */
export function deleteFlow(flowId: string): void {
	const id = Number(flowId);
	// Children first (steps, edges and joins reference the flow); test flows never have runs.
	// "Join" is an SQL reserved word: quoted, and doubled inside the ObjectScript string.
	const children = ['sentai_model.Edge', 'sentai_model.""Join""', 'sentai_model.Step']
		.map((table) => `do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM ${table} WHERE flow = ?",${id})`)
		.join('\n');
	const out = irisSys(
		`${children}\nset sc=##class(sentai.model.Flow).%DeleteId(${id}) write "RESULT:",$select(sc=1:"OK",1:$system.Status.GetErrorText(sc)),!`,
		'IRISAPP'
	);
	const result = /RESULT:(.*)/.exec(out)?.[1]?.trim();
	if (result !== 'OK') throw new Error(`could not delete flow ${flowId}: ${result ?? 'no answer'}`);
}

// --- spec 010: deleting test flows that have runs (T038, T061) --------------------------------

/** The dev compose container; destructive test setup runs nowhere else. */
const DEV_CONTAINER = 'sentai-task-iris-1';
export const EXAMPLE_FLOW_NAME = 'Example: storage health check';
/** Names this feature's tests and quickstart create; nothing else may be deleted. */
const TEST_FLOW_PREFIXES = ['us17-', 'us18-', 'us19-', 'us20-', 'us21-', 'perf-', 'QS ', 'plan010-probe-'];

/**
 * Throws `refused: …` unless this is the local dev instance and `expectedName` is a flow this
 * feature's tests may delete. Checked before any IRIS session is opened.
 */
export function assertDevInstance(expectedName: string): void {
	const base = new URL(process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:52773/csp/sentai/');
	if (!['localhost', '127.0.0.1'].includes(base.hostname)) throw new Error(`refused: base URL ${base.host} is not the local dev instance`);
	const container = process.env.SENTAI_CONTAINER ?? DEV_CONTAINER;
	if (container !== DEV_CONTAINER) throw new Error(`refused: container ${container} is not ${DEV_CONTAINER}`);
	if (expectedName !== EXAMPLE_FLOW_NAME && !TEST_FLOW_PREFIXES.some((p) => expectedName.startsWith(p))) {
		throw new Error(`refused: "${expectedName}" is not a test flow name`);
	}
}

/**
 * Deletes a flow **and its runs** (LogEntry, StepRun, Run, then Edge, Join, Step, Flow). Guarded
 * twice: `assertDevInstance` here, and in IRIS the namespace must be IRISAPP and the flow's name
 * must equal `expectedName`, or it prints REFUSED and deletes nothing.
 */
export function deleteFlowWithRuns(flowId: string, expectedName: string): void {
	assertDevInstance(expectedName);
	const id = Number(flowId);
	if (!Number.isInteger(id) || id <= 0) throw new Error(`refused: flow id ${flowId} is not a number`);
	const name = expectedName.replaceAll('"', '""');
	const sql = (statement: string) => `do ##class(%SQL.Statement).%ExecDirect(,"${statement}",${id})`;
	const deletes = [
		sql('DELETE FROM sentai_model.LogEntry WHERE run IN (SELECT ID FROM sentai_model.Run WHERE flow = ?)'),
		sql('DELETE FROM sentai_model.StepRun WHERE run IN (SELECT ID FROM sentai_model.Run WHERE flow = ?)'),
		sql('DELETE FROM sentai_model.Run WHERE flow = ?'),
		sql('DELETE FROM sentai_model.Edge WHERE flow = ?'),
		sql('DELETE FROM sentai_model.""Join"" WHERE flow = ?'),
		sql('DELETE FROM sentai_model.Step WHERE flow = ?'),
		`set sc=##class(sentai.model.Flow).%DeleteId(${id})`,
		`write "RESULT:",$select(sc=1:"OK",1:$system.Status.GetErrorText(sc)),!`
	].join(' ');
	// One terminal line: a `quit` on its own line would not stop the lines after it.
	const script =
		`if $namespace'="IRISAPP" { write "RESULT:REFUSED namespace ",$namespace,! } ` +
		`else { set f=##class(sentai.model.Flow).%OpenId(${id}) ` +
		`if '$isobject(f) { write "RESULT:REFUSED no flow ${id}",! } ` +
		`elseif f.name'="${name}" { write "RESULT:REFUSED name mismatch",! } ` +
		`else { kill f ${deletes} } }`;
	const result = /RESULT:(.*)/.exec(irisSys(script, 'IRISAPP'))?.[1]?.trim();
	if (result !== 'OK') throw new Error(result?.startsWith('REFUSED') ? `refused: ${result}` : `could not delete flow ${flowId}: ${result ?? 'no answer'}`);
}
