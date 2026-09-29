"""Spec 015 acceptance on the dev stack (quickstart; SC-001 local and remote, SC-002, SC-003, SC-004, SC-005).

    python scripts/schedule-evidence/acceptance.py [--base http://localhost:52773] [--skip-failure]

What it does, against the real platform (nothing is simulated):
  1. creates a run-as account `sched-test` (random password, never printed) on the primary and on
     iris-target, with the demo's least-privilege resources plus `SentaiSchedule:U` on the primary;
  2. creates a `us28-accept-*` flow: an integrity check on iris-target, then a database size report
     on the primary (in-process), and schedules it daily two minutes ahead, as `sched-test`;
  3. waits for the platform to fire the task and for the run to complete, marked `scheduled`,
     dispatched by `sched-test`, the in-process step executed as `sched-test`;
  4. replaces the schedule (still one task), then takes `SentaiSchedule:U` away from the account and
     fires again: a failed run whose log gives the platform's #822 refusal (SC-004);
  5. unschedules: no task, no secret, `scheduled: false` (SC-003, SC-005);
  6. searches the product's globals for the password (SC-002);
  7. removes the flow, its runs, the account and its role.

The operator is IRIS_USER/IRIS_PASSWORD (default _SYSTEM/SYS, the dev stack). Prints PASS/FAIL per
check and exits 1 on any failure.
"""
import argparse, base64, datetime, json, os, secrets, subprocess, sys, time, urllib.error, urllib.request

API = "/csp/sentai/api/v1"
PRIMARY = "sentai-task-iris-1"
TARGET = "sentai-task-iris-target-1"
ROLE = "SentaiSchedTest"
USER = "sched-test"
PRIMARY_RESOURCES = "%DB_IRISAPP_CODE:R,%DB_IRISAPP_DATA:RW,%Admin_Manage:U,%DB_IRISSYS:RW,%Admin_Operate:U,SentaiSchedule:U"
TARGET_RESOURCES = "%DB_USER:R,%Admin_Manage:U,%DB_IRISSYS:RW,%Admin_Operate:U"
results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(("PASS " if ok else "FAIL ") + name + (f" — {detail}" if detail else ""), flush=True)


def call(base, method, path, body=None, auth=None):
    headers = {"Content-Type": "application/json"}
    if callable(auth):
        auth = auth()  # a fresh operator token: access tokens last 60 s
    if auth:
        headers["Authorization"] = auth
    req = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(), method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            text = r.read().decode()
            return r.status, (json.loads(text) if text else {})
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            return e.code, json.loads(text)
        except ValueError:
            return e.code, text


def token(base, user, password):
    auth = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()
    s, b = call(base, "POST", "/api/admin/login", {}, auth)
    if s != 200:
        raise SystemExit(f"operator sign-in refused: HTTP {s}")
    return "Bearer " + b["access_token"]


def session(container, namespace, script):
    """Runs ObjectScript lines through `iris session` on stdin (nothing on a command line)."""
    out = subprocess.run(["docker", "exec", "-i", container, "iris", "session", "IRIS", "-U", namespace], input=script + "\nhalt\n",
                         capture_output=True, text=True, encoding="utf-8", errors="replace", env={**os.environ, "MSYS_NO_PATHCONV": "1"})
    return out.stdout


def result_of(out):
    for line in out.splitlines():
        if "RESULT:" in line:
            return line.split("RESULT:", 1)[1].strip()
    return "no answer"


def account(container, resources, password, sql):
    lines = [
        f'set pw=$zconvert("{password}","I","URL")',
        f'set res="{resources}"',
        f'if ##class(Security.Roles).Exists("{ROLE}") {{ kill r set r("Resources")=res set sc=##class(Security.Roles).Modify("{ROLE}",.r) }} else {{ set sc=##class(Security.Roles).Create("{ROLE}","spec 015 acceptance run-as",res) }}',
        f'if ##class(Security.Users).Exists("{USER}") {{ kill u set u("Password")=pw,u("Roles")="{ROLE}",u("Enabled")=1,u("ChangePassword")=0 set sc=##class(Security.Users).Modify("{USER}",.u) }} else {{ set sc=##class(Security.Users).Create("{USER}","{ROLE}",pw,"spec 015 acceptance run-as") }}',
    ]
    if sql:
        lines += ['new $namespace set $namespace="IRISAPP"',
                  f'set st=##class(%SQL.Statement).%ExecDirect(,"GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA sentai_model TO {ROLE}")',
                  f'set st=##class(%SQL.Statement).%ExecDirect(,"GRANT EXECUTE ON %SYS.DatabaseQuery_FreeSpace TO {ROLE}")']
    lines.append('write "RESULT:",$select(sc=1:"OK",1:$system.Status.GetErrorText(sc)),!')
    lines.append("kill pw")
    return result_of(session(container, "%SYS", "\n".join(lines)))


def set_role_resources(container, resources):
    return result_of(session(container, "%SYS", f'kill r set r("Resources")="{resources}" set sc=##class(Security.Roles).Modify("{ROLE}",.r) write "RESULT:",$select(sc=1:"OK",1:$system.Status.GetErrorText(sc)),!'))


def remove_account(container):
    session(container, "%SYS", f'set sc=##class(Security.Users).Delete("{USER}")\nset sc=##class(Security.Roles).Delete("{ROLE}")')


def ahead(instance_time, minutes):
    now = datetime.datetime.strptime(instance_time[:19], "%Y-%m-%d %H:%M:%S")
    at = (now + datetime.timedelta(minutes=minutes + (1 if now.second > 40 else 0))).replace(second=0)
    return at


def wait_run(base, auth, flow_id, after_seq, until, want_terminal=True):
    """The first scheduled run of the flow newer than `after_seq`, once terminal (or up to `until`)."""
    while time.time() < until:
        s, page = call(base, "GET", f"{API}/runs?flowId={flow_id}&trigger=scheduled&limit=5", auth=auth)
        if s == 200:
            fresh = [r for r in page if r["seq"] > after_seq]
            if fresh:
                run = fresh[-1]
                if not want_terminal or run["state"] in ("completed", "failed", "cancelled"):
                    return run
        time.sleep(10)
    return None


def flow_tasks(base, auth, flow_id):
    s, body = call(base, "GET", "/api/admin/v2/tasks", auth=auth)
    rows = body.get("result", []) if s == 200 and isinstance(body, dict) else []
    return [r for r in rows if str(r.get("Name", "")).startswith(f"SentaiTask: {flow_id} ") or str(r.get("Name", "")).startswith(f"SentaiTask: {flow_id}#")]


def flow_secrets(base, auth, flow_id):
    s, body = call(base, "GET", "/api/admin/v2/wallet/secrets?collection=SentaiTask", auth=auth)
    rows = body.get("result", []) if s == 200 and isinstance(body, dict) else []
    return [r for r in rows if f".flow{flow_id}-" in str(r.get("Name", ""))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://localhost:52773")
    ap.add_argument("--skip-failure", action="store_true", help="skip the start-failure firing (SC-004)")
    args = ap.parse_args()
    base = args.base
    op_user, op_password = os.environ.get("IRIS_USER", "_SYSTEM"), os.environ.get("IRIS_PASSWORD", "SYS")
    password = "St" + secrets.token_urlsafe(18)
    flow_id = None
    try:
        check("run-as account on the primary", account(PRIMARY, PRIMARY_RESOURCES, password, True) == "OK")
        check("run-as account on iris-target", account(TARGET, TARGET_RESOURCES, password, False) == "OK")

        auth = lambda: token(base, op_user, op_password)
        flow = {"name": f"us28-accept-{secrets.token_hex(3)}", "defaultCategory": "Default",
                "steps": [{"id": "01", "type": "integrity-check", "taskName": "Integrity check: USER on iris-target", "namespace": "USER", "target": "iris-target", "wqmCategory": "Default", "timeoutMinutes": 30, "parameters": {}},
                          {"id": "02", "type": "db-size-report", "taskName": "Database size report", "namespace": "%SYS", "wqmCategory": "Default", "timeoutMinutes": 10, "parameters": {}}],
                "edges": [{"source": "01", "target": "02"}], "joins": [], "canvasGeometry": {"nodes": {"01": {"x": 40, "y": 60}, "02": {"x": 400, "y": 60}}}}
        s, created = call(base, "POST", f"{API}/flows", flow, auth)
        check("flow created", s in (200, 201), f"HTTP {s}")
        flow_id = created["id"]

        s, before = call(base, "GET", f"{API}/flows/{flow_id}/schedule", auth=auth)
        check("GET schedule of an unscheduled flow", s == 200 and before.get("scheduled") is False, json.dumps(before)[:200])
        at = ahead(before["instanceTime"], 2)
        body = {"schedule": {"kind": "daily", "startTime": at.strftime("%H:%M")}, "runAs": USER, "password": password,
                "targetPasswords": [{"target": "iris-target", "password": password}]}

        s, wrong = call(base, "POST", f"{API}/flows/{flow_id}/schedule", {**body, "password": password + "x"}, auth)
        check("wrong run-as password is refused, nothing created", s == 422 and wrong.get("code") == "CREDENTIAL_REFUSED" and not flow_tasks(base, auth, flow_id), f"HTTP {s}")
        s, old = call(base, "POST", f"{API}/flows/{flow_id}/schedule", {"scheduleSpec": "WEEKLY SAT 03:00"}, auth)
        check("the spec 001 body is refused with SCHEDULE_FORMAT", s == 400 and old.get("code") == "SCHEDULE_FORMAT", f"HTTP {s}")

        s, made = call(base, "POST", f"{API}/flows/{flow_id}/schedule", body, auth)
        check("schedule created", s == 201, f"HTTP {s} {'' if s == 201 else json.dumps(made)[:300]}")
        check("the platform's next run is the chosen time", made.get("nextRun", "")[:16] == at.strftime("%Y-%m-%d %H:%M"), made.get("nextRun"))
        check("one task, running as the run-as account", [t.get("Id") for t in flow_tasks(base, auth, flow_id)] == [made.get("taskId")])
        check("two wallet secrets (primary, iris-target)", len(flow_secrets(base, auth, flow_id)) == 2)
        s, info = call(base, "GET", f"/api/admin/v2/task?id={made.get('taskId')}", auth=auth)
        check("task RunAsUser", s == 200 and info.get("result", {}).get("RunAsUser") == USER, f"HTTP {s}")

        # SC-001: the platform fires; the run completes (local in-process step and remote step).
        s, runs = call(base, "GET", f"{API}/runs?flowId={flow_id}&limit=1", auth=auth)
        last_seq = runs[0]["seq"] if s == 200 and runs else 0
        wait_until = time.mktime(at.timetuple()) - time.mktime(datetime.datetime.strptime(before["instanceTime"][:19], "%Y-%m-%d %H:%M:%S").timetuple()) + time.time() + 240
        print(f"… waiting for the task to fire at {at:%H:%M} (instance time)", flush=True)
        run = wait_run(base, auth, flow_id, last_seq, wait_until)
        check("SC-001 a scheduled run started and ended", run is not None)
        if run:
            s, detail = call(base, "GET", f"{API}/runs/{run['guid']}", auth=auth)
            check("SC-001 the run completed", detail.get("state") == "completed", json.dumps(detail)[:600])
            check("run marked scheduled, dispatched by the run-as account", detail.get("trigger") == "scheduled" and detail.get("dispatchedBy") == USER)
            steps = {x["stepId"]: x for x in detail.get("steps", [])}
            check("in-process step executed as the run-as account", steps.get("02", {}).get("executedAs") == USER, json.dumps(steps.get("02", {}))[:200])
            check("remote step ran on iris-target", steps.get("01", {}).get("executedOn") == "iris-target" and steps.get("01", {}).get("state") == "completed")
            # The log is newest first: the run's first entry is the last one.
            first = (detail.get("log") or [{}])[-1].get("message", "")
            check("first log entry names the schedule", first.startswith("Run started by the schedule of flow"), first)
            last_seq = run["seq"]

        # SC-003/SC-005: replace keeps one task; the old secrets go.
        s, g = call(base, "GET", f"{API}/flows/{flow_id}/schedule", auth=auth)
        at2 = ahead(g["instanceTime"], 2)
        body["schedule"] = {"kind": "daily", "startTime": at2.strftime("%H:%M")}
        s, made2 = call(base, "POST", f"{API}/flows/{flow_id}/schedule", body, auth)
        check("replace: one task, a new id", s == 201 and [t.get("Id") for t in flow_tasks(base, auth, flow_id)] == [made2.get("taskId")] and made2.get("taskId") != made.get("taskId"))
        check("replace: still two secrets (new generation)", len(flow_secrets(base, auth, flow_id)) == 2 and all("-g2-" in x["Name"] for x in flow_secrets(base, auth, flow_id)))

        # SC-004: the account may no longer use the wallet: the start fails with the platform's text.
        if not args.skip_failure:
            check("SentaiSchedule:U taken from the run-as role", set_role_resources(PRIMARY, PRIMARY_RESOURCES.replace(",SentaiSchedule:U", "")) == "OK")
            print(f"… waiting for the task to fire at {at2:%H:%M} (instance time)", flush=True)
            failed = wait_run(base, auth, flow_id, last_seq, time.time() + 240)
            check("SC-004 a failed scheduled run is recorded", failed is not None and failed["state"] == "failed", json.dumps(failed)[:300])
            if failed:
                s, detail = call(base, "GET", f"{API}/runs/{failed['guid']}", auth=auth)
                text = (detail.get("log") or [{}])[-1].get("message", "")
                check("SC-004 the log gives the platform's refusal", text.startswith("Scheduled run could not start: could not read the stored credential for primary") and "#822" in text, text)
            s, info = call(base, "GET", f"/api/admin/v2/task/info?id={made2.get('taskId')}", auth=auth)
            # The platform reports the task's last error status in `Status` (its %Status, serialized).
            last = info.get("result", {}) if s == 200 else {}
            check("SC-004 the task history shows the error", "could not start" in str(last.get("Error", "")) + str(last.get("Status", "")), f"HTTP {s}")
            set_role_resources(PRIMARY, PRIMARY_RESOURCES)

        # SC-003: unschedule removes everything; twice is harmless.
        s, gone = call(base, "DELETE", f"{API}/flows/{flow_id}/schedule", auth=auth)
        check("unschedule", s == 200 and gone.get("residue") == [], json.dumps(gone)[:200])
        check("no task left", flow_tasks(base, auth, flow_id) == [])
        check("no secret left", flow_secrets(base, auth, flow_id) == [])
        s, again = call(base, "DELETE", f"{API}/flows/{flow_id}/schedule", auth=auth)
        check("unschedule again is harmless", s == 200 and again.get("removedTasks") == [])
        s, after = call(base, "GET", f"{API}/flows/{flow_id}/schedule", auth=auth)
        check("GET schedule: not scheduled", after.get("scheduled") is False)

        # SC-002: the password is in none of the product's globals.
        # The password goes on stdin, never on a command line.
        scan = subprocess.run(["docker", "exec", "-i", PRIMARY, "iris", "session", "IRIS", "-U", "IRISAPP"],
                              input=scan_script(password), capture_output=True, text=True, encoding="utf-8", errors="replace",
                              env={**os.environ, "MSYS_NO_PATHCONV": "1"}).stdout
        check("SC-002 password in no product global", result_of(scan) == "CLEAN", result_of(scan))
    finally:
        if flow_id:
            auth = token(base, op_user, op_password)
            call(base, "DELETE", f"{API}/flows/{flow_id}/schedule", auth=auth)
            session(PRIMARY, "IRISAPP", f'do ##class(sentai.demo.Demo).DeleteFlow({int(flow_id)})')
        remove_account(PRIMARY)
        remove_account(TARGET)
    print(f"{sum(results)}/{len(results)} checks passed", flush=True)
    sys.exit(0 if all(results) else 1)


def scan_script(password):
    return "\n".join([
        'set pw=$zconvert("' + password + '","I","URL")',
        'set found="",name="^sentai" for { set name=$order(^$GLOBAL(name)) quit:(name="")||($extract($piece(name,"^",2),1,6)\'="sentai")  set node=name if $data(@node)#10,$get(@node)[pw { set found=node quit } for { set node=$query(@node) quit:node=""  if (node[pw)||($get(@node)[pw) { set found=node quit } } quit:found\'="" }',
        'write "RESULT:",$select(found="":"CLEAN",1:"FOUND"),!',
        "kill pw",
        "halt", ""])


if __name__ == "__main__":
    main()
