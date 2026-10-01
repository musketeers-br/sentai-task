"""Spec 020 acceptance on the dev stack (SC-001 scheduled, SC-003, SC-004).

    python scripts/security-evidence/acceptance.py [--base http://localhost:52773]

Against the real platform (nothing simulated):
  1. creates a throw-away x509 credential `sentai-e2e-020-*` on the primary whose certificate
     expires in 10 days (public certificate only; the key file is deleted by the same command);
  2. creates a run-as account `sched-test` (random password, never printed) with the demo's
     resources plus `%Admin_Secure:U` and the OAuth 2.0 administration resources (security reads) and `SentaiSchedule:U` (spec 015);
  3. schedules a `us29-accept-*` flow — Certificate expiry check (warnDays 30), then OAuth
     inventory — daily two minutes ahead as `sched-test`, and waits for the Task Manager to fire;
  4. asserts a failed scheduled run whose certificate step names the credential, and an OAuth step
     that completed with the platform's "not configured" text;
  5. scans the stored results for key material (SC-004);
  6. unschedules and removes the flow, the account and the credential.

Reuses the helpers of scripts/schedule-evidence/acceptance.py. Prints PASS/FAIL per check and
exits 1 on any failure.
"""
import argparse, importlib.util, json, os, pathlib, secrets, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("schedacc", HERE.parent / "schedule-evidence" / "acceptance.py")
sa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sa)

API = sa.API
# Security reads need %Admin_Secure; OAuth reads the three OAuth 2.0 administration resources
# (evidence t001, section 5).
RESOURCES = sa.PRIMARY_RESOURCES + ",%Admin_Secure:U,%Admin_OAuth2_Client:U,%Admin_OAuth2_Server:U,%Admin_OAuth2_Registration:U"
ENV = {**os.environ, "MSYS_NO_PATHCONV": "1"}


def create_certificate(alias, days):
    subprocess.run(["docker", "exec", sa.PRIMARY, "sh", "-c",
                    f"openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/{alias}.key -out /tmp/{alias}.crt -days {days} -subj /CN={alias} 2>/dev/null; rm -f /tmp/{alias}.key"],
                   check=True, env=ENV)
    out = sa.session(sa.PRIMARY, "%SYS", f'set x=##class(%SYS.X509Credentials).%New(),x.Alias="{alias}" set sc=x.LoadCertificate("/tmp/{alias}.crt") set:sc sc=x.%Save() write "RESULT:",$select(sc=1:"OK",1:$system.Status.GetErrorText(sc)),!')
    subprocess.run(["docker", "exec", "-u", "root", sa.PRIMARY, "rm", "-f", f"/tmp/{alias}.crt"], env=ENV)
    return sa.result_of(out)


def delete_certificate(alias):
    sa.session(sa.PRIMARY, "%SYS", f'if ##class(%SYS.X509Credentials).%ExistsId("{alias}") {{ set sc=##class(%SYS.X509Credentials).%DeleteId("{alias}") }}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://localhost:52773")
    args = ap.parse_args()
    base = args.base
    op_user, op_password = os.environ.get("IRIS_USER", "_SYSTEM"), os.environ.get("IRIS_PASSWORD", "SYS")
    auth = lambda: sa.token(base, op_user, op_password)
    password = "St" + secrets.token_urlsafe(18)
    alias = f"sentai-e2e-020-{secrets.token_hex(3)}"
    flow_id = None
    try:
        sa.check("test certificate expiring in 10 days", create_certificate(alias, 10) == "OK")
        sa.check("run-as account with security reads", sa.account(sa.PRIMARY, RESOURCES, password, True) == "OK")

        flow = {"name": f"us29-accept-{secrets.token_hex(3)}", "defaultCategory": "Default",
                "steps": [{"id": "01", "type": "certificate-expiry-check", "taskName": "Certificate expiry check", "namespace": "%SYS", "wqmCategory": "Default", "timeoutMinutes": 10, "parameters": {"warnDays": 30}},
                          {"id": "02", "type": "oauth-inventory", "taskName": "OAuth inventory", "namespace": "%SYS", "wqmCategory": "Default", "timeoutMinutes": 10, "parameters": {}}],
                "edges": [], "joins": [], "canvasGeometry": {"nodes": {"01": {"x": 40, "y": 60}, "02": {"x": 400, "y": 60}}}}
        s, created = sa.call(base, "POST", f"{API}/flows", flow, auth)
        sa.check("flow created", s in (200, 201), f"HTTP {s}")
        flow_id = created["id"]

        s, before = sa.call(base, "GET", f"{API}/flows/{flow_id}/schedule", auth=auth)
        at = sa.ahead(before["instanceTime"], 2)
        s, made = sa.call(base, "POST", f"{API}/flows/{flow_id}/schedule",
                          {"schedule": {"kind": "daily", "startTime": at.strftime("%H:%M")}, "runAs": sa.USER, "password": password, "targetPasswords": []}, auth)
        sa.check("scheduled as the run-as account", s == 201, f"HTTP {s} {'' if s == 201 else json.dumps(made)[:300]}")

        print(f"… waiting for the task to fire at {at:%H:%M} (instance time)", flush=True)
        run = sa.wait_run(base, auth, flow_id, 0, time.time() + 240)
        sa.check("SC-001 a scheduled run fired and ended", run is not None)
        if run:
            s, detail = sa.call(base, "GET", f"{API}/runs/{run['guid']}", auth=auth)
            steps = {x["stepId"]: x for x in detail.get("steps", [])}
            cert, oauth = steps.get("01", {}), steps.get("02", {})
            sa.check("SC-001 the scheduled run failed on the certificate", detail.get("state") == "failed" and cert.get("state") == "failed", f"run {detail.get('state')}, step {cert.get('state')}")
            sa.check("SC-001 the reason names the certificate", alias in cert.get("failureReason", "") and "within 30 days" in cert.get("failureReason", ""), cert.get("failureReason", "")[:200])
            sa.check("the check ran as the run-as account", cert.get("executedAs") == sa.USER, cert.get("executedAs"))
            sa.check("SC-003 OAuth not configured completes", oauth.get("state") == "completed" and "#8864" in json.dumps(oauth.get("result", {})), oauth.get("state"))
            text = json.dumps(detail)
            sa.check("SC-004 no key material in the stored results", not any(k in text for k in ("PRIVATE KEY", "PrivateKeyPassword", "ClientSecret")))

        s, gone = sa.call(base, "DELETE", f"{API}/flows/{flow_id}/schedule", auth=auth)
        sa.check("unscheduled, no task left", s == 200 and sa.flow_tasks(base, auth, flow_id) == [])
    finally:
        if flow_id:
            sa.call(base, "DELETE", f"{API}/flows/{flow_id}/schedule", auth=auth)
            sa.session(sa.PRIMARY, "IRISAPP", f"do ##class(sentai.demo.Demo).DeleteFlow({int(flow_id)})")
        sa.remove_account(sa.PRIMARY)
        delete_certificate(alias)
    print(f"{sum(sa.results)}/{len(sa.results)} checks passed", flush=True)
    sys.exit(0 if all(sa.results) else 1)


if __name__ == "__main__":
    main()
