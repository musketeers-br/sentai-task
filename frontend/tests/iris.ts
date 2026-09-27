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
	const children = ['sentai_model.Edge', 'sentai_model.Join', 'sentai_model.Step']
		.map((table) => `do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM ${table} WHERE flow = ?",${id})`)
		.join('\n');
	const out = irisSys(
		`${children}\nset sc=##class(sentai.model.Flow).%DeleteId(${id}) write "RESULT:",$select(sc=1:"OK",1:$system.Status.GetErrorText(sc)),!`,
		'IRISAPP'
	);
	const result = /RESULT:(.*)/.exec(out)?.[1]?.trim();
	if (result !== 'OK') throw new Error(`could not delete flow ${flowId}: ${result ?? 'no answer'}`);
}
