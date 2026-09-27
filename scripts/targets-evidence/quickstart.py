"""Spec 008 quickstart (a)-(f) against the compose stack (iris + iris-target).

Runs every call of specs/008-distributed-targets/quickstart.md through the product API on the
host (http://localhost:52773), records status + body per call with every token and password
redacted, and writes specs/008-distributed-targets/evidence/quickstart-http-<date>.json.

Credentials come from IRIS_USER / IRIS_PASSWORD (default: the dev image's _SYSTEM/SYS). A temporary
user created on the target for the mismatch case gets a generated password and is deleted at the
end. Needs docker (stops and restarts the target for (b) and (e)).
"""
import base64, datetime, json, os, secrets, subprocess, sys, time, urllib.request, urllib.error

HOST = os.environ.get("SENTAI_HOST", "http://localhost:52773")
API = HOST + "/csp/sentai/api/v1"
USER = os.environ.get("IRIS_USER", "_SYSTEM")
PASSWORD = os.environ.get("IRIS_PASSWORD", "SYS")
PRIMARY = os.environ.get("SENTAI_CONTAINER", "sentai-task-iris-1")
TARGET_CONTAINER = os.environ.get("SENTAI_TARGET_CONTAINER", "sentai-task-iris-target-1")
TARGET = "iris-target"
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "specs", "008-distributed-targets", "evidence")

secrets_seen = {PASSWORD}
calls = []


def redact(value):
    if isinstance(value, dict):
        return {k: ("<REDACTED>" if k.lower() in ("access_token", "refresh_token", "accesstoken", "refreshtoken", "password") else redact(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value]
    return value


def http(method, url, body=None, headers=None, section="", note=""):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json", **(headers or {})})
    started = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            status, text = res.status, res.read().decode()
    except urllib.error.HTTPError as e:
        status, text = e.code, e.read().decode()
    elapsed = round(time.time() - started, 2)
    try:
        parsed = json.loads(text) if text else None
    except ValueError:
        parsed = text
    for key in ("access_token", "refresh_token", "accessToken", "refreshToken"):
        if isinstance(parsed, dict) and parsed.get(key):
            secrets_seen.add(parsed[key])
    calls.append({"section": section, "note": note, "request": {"method": method, "path": url.replace(HOST, ""), "body": redact(body)},
                  "response": {"status": status, "elapsedSeconds": elapsed, "body": redact(parsed)}})
    return status, parsed


def primary_token():
    auth = base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
    status, body = http("POST", HOST + "/api/admin/login", {}, {"Authorization": "Basic " + auth}, "setup", "primary sign-in")
    assert status == 200, body
    return body


def iris(container, namespace, script):
    out = subprocess.run(["docker", "exec", "-i", container, "iris", "session", "iris", "-U", namespace],
                         input=script + "\nhalt\n", capture_output=True, text=True, env={**os.environ, "MSYS_NO_PATHCONV": "1"})
    return out.stdout


def wait_healthy(container):
    for _ in range(90):
        state = subprocess.run(["docker", "inspect", "-f", "{{.State.Health.Status}}", container], capture_output=True, text=True).stdout.strip()
        if state == "healthy":
            return
        time.sleep(2)
    raise SystemExit(f"{container} did not become healthy")


def H(token):
    return {"Authorization": "Bearer " + token}


def flow(h, name, steps, edges=(), joins=()):
    status, body = http("POST", API + "/flows", {"name": f"{name} {secrets.token_hex(3)}", "defaultCategory": "Default", "steps": steps, "edges": list(edges), "joins": list(joins)}, h, "setup", "seed flow")
    assert status == 201, body
    return body["id"]


def ic(step_id, task, namespace="USER", target=None, timeout=30, directory="/usr/irissys/mgr/user/"):
    s = {"id": step_id, "type": "integrity-check", "taskName": task, "namespace": namespace, "runAsUser": "irisadm", "wqmCategory": "Default", "timeoutMinutes": timeout}
    if target:
        s["target"] = target
    else:
        s["databaseDirectory"] = directory
    return s


def sign_in(h, user=USER, password=PASSWORD, section="(b)"):
    return http("POST", f"{API}/targets/{TARGET}/sign-in", {"user": user, "password": password}, h, section, f"sign-in as {user}")


def dispatch(flow_id, target_refresh, section, note):
    pair = primary_token()
    body = {"confirmations": [], "runCredential": {"refreshToken": pair["refresh_token"]}}
    if target_refresh is not None:
        body["targetCredentials"] = [{"target": TARGET, "refreshToken": target_refresh}]
    return http("POST", f"{API}/flows/{flow_id}/dispatch", body, H(pair["access_token"]), section, note)


def follow(guid, section, until=lambda run: run["state"] != "running", limit=600):
    started = time.time()
    while time.time() - started < limit:
        status, run = http("GET", f"{API}/runs/{guid}", None, H(primary_token()["access_token"]), "poll", "")
        calls.pop()  # polls are summarised by the final read below
        calls.pop()  # and the token sign-in behind them
        if until(run):
            break
        time.sleep(5)
    status, run = http("GET", f"{API}/runs/{guid}", None, H(primary_token()["access_token"]), section, "run read")
    return run


def main():
    # The primary's tokens live 60 s: every call gets a fresh one.
    def h():
        return H(primary_token()["access_token"])
    http("DELETE", f"{API}/targets/{TARGET}", None, h(), "setup", "start clean")

    # (a) registry
    http("POST", API + "/targets", {"name": TARGET, "baseUrl": "http://iris-target:52773", "description": "demo target (compose)"}, h(), "(a)", "register (demo allowance set in iris.script)")
    http("GET", API + "/targets", None, h(), "(a)", "list")
    http("POST", API + "/targets", {"name": TARGET, "baseUrl": "http://x:1"}, h(), "(a)", "duplicate name -> 409")
    iris(PRIMARY, "IRISAPP", 'set ^||a=$g(^sentai("config","allowInsecureTargets")) kill ^sentai("config","allowInsecureTargets")')
    http("POST", API + "/targets", {"name": "insecure-demo", "baseUrl": "http://example.com:52773"}, h(), "(a)", "http non-loopback without the allowance -> 400 INSECURE_TARGET")
    iris(PRIMARY, "IRISAPP", 'set ^sentai("config","allowInsecureTargets")=1')

    # (b) sign-in and status
    status, pair = sign_in(h())
    tt, tr = pair["accessToken"], pair["refreshToken"]
    th = {**h(), "X-Sentai-Target-Authorization": "Bearer " + tt}
    http("GET", f"{API}/targets/{TARGET}/status", None, th, "(b)", "status, reachable (SC-006 < 3 s)")
    sign_in(h(), USER, "wrong-" + secrets.token_hex(3))
    subprocess.run(["docker", "stop", TARGET_CONTAINER], capture_output=True)
    http("GET", f"{API}/targets/{TARGET}/status", None, th, "(b)", "status with the target container stopped")
    subprocess.run(["docker", "start", TARGET_CONTAINER], capture_output=True)
    wait_healthy(TARGET_CONTAINER)

    # (c) refusals
    status, pair = sign_in(h(), section="(c)")
    tt, tr = pair["accessToken"], pair["refreshToken"]
    creds = {"targetCredentials": [{"target": TARGET, "accessToken": tt}]}
    f_nope = flow(h(), "QS nope", [ic("01", "on an unknown target", target="nope")])
    http("POST", f"{API}/flows/{f_nope}/validate", creds, h(), "(c)", "TARGET_NOT_FOUND")
    f_ok = flow(h(), "QS remote", [ic("01", "on iris-target", target=TARGET)])
    http("POST", f"{API}/targets/{TARGET}/online", {"online": False}, h(), "(c)", "set offline")
    http("POST", f"{API}/flows/{f_ok}/validate", creds, h(), "(c)", "TARGET_OFFLINE")
    http("POST", f"{API}/targets/{TARGET}/online", {"online": True}, h(), "(c)", "set online")
    f_inproc = flow(h(), "QS in-process", [{"id": "01", "type": "db-size-report", "taskName": "db size on target", "namespace": "USER", "runAsUser": "irisadm", "wqmCategory": "Default", "target": TARGET}])
    http("POST", f"{API}/flows/{f_inproc}/validate", creds, h(), "(c)", "STEP_TYPE_NOT_REMOTE_CAPABLE")
    http("POST", f"{API}/flows/{f_ok}/validate", {}, h(), "(c)", "no credential for the target -> warning TARGET_NOT_VERIFIED")
    http("POST", f"{API}/flows/{f_ok}/validate", creds, h(), "(c)", "with a credential: the target's answers, no finding")
    f_ns = flow(h(), "QS namespace", [ic("01", "IRISAPP on iris-target", namespace="IRISAPP", target=TARGET)])
    http("POST", f"{API}/flows/{f_ns}/validate", creds, h(), "(c)", "NAMESPACE_NOT_FOUND from the target's own namespaces")
    dispatch(f_ok, None, "(c)", "dispatch without targetCredentials -> 400 TARGET_CREDENTIAL_MISSING")
    other, other_pw = "qs_other_" + secrets.token_hex(3), secrets.token_urlsafe(18)
    secrets_seen.add(other_pw)
    iris(TARGET_CONTAINER, "%SYS", f'set sc=##class(Security.Users).Create("{other}","%All","{other_pw}","spec 008 quickstart temporary user")')
    try:
        status, other_pair = sign_in(h(), other, other_pw, "(c)")
        dispatch(f_ok, other_pair["refreshToken"], "(c)", "another user's target credential -> 403 TARGET_CREDENTIAL_USER_MISMATCH")
    finally:
        iris(TARGET_CONTAINER, "%SYS", f'set sc=##class(Security.Users).Delete("{other}")')

    # (d) the demo flow
    status, pair = sign_in(h(), section="(d)")
    demo = flow(h(), "QS DPI-I-588 demo", [ic("01", "IC USER (primary)"), ic("02", "IC IRISAPP (primary)", "IRISAPP", directory="/data/IRISAPP_DATA/"), ic("03", "IC USER (iris-target)", target=TARGET), ic("04", "IC after fan-in")],
                [{"source": s, "target": "04"} for s in ("01", "02", "03")], [{"target": "04", "policy": "ALL_MUST_SUCCEED"}])
    status, run = dispatch(demo, pair["refreshToken"], "(d)", "dispatch the demo flow")
    demo_run = follow(run["guid"], "(d)")

    # (e) target down mid-run
    status, pair = sign_in(h(), section="(e)")
    down = flow(h(), "QS target down", [ic("01", "IC USER (primary)"), ic("03", "IC USER (iris-target), 1 min timeout", target=TARGET, timeout=1)])
    status, run = dispatch(down, pair["refreshToken"], "(e)", "dispatch, then stop the target once 03 runs")
    follow(run["guid"], "(e) running", until=lambda r: any(s["stepId"] == "03" and s["state"] != "queued" for s in r["steps"]), limit=120)
    subprocess.run(["docker", "stop", TARGET_CONTAINER], capture_output=True)
    down_run = follow(run["guid"], "(e)", limit=600)
    subprocess.run(["docker", "start", TARGET_CONTAINER], capture_output=True)
    wait_healthy(TARGET_CONTAINER)

    # (f) residue
    guids = [demo_run["guid"], down_run["guid"]]
    cred = iris(PRIMARY, "IRISAPP", "write \"CRED \"" + "".join(f",$d(^IRIS.Temp.sentaiTargetCred(\"{g}\"))" for g in guids) + ",!")
    # One IRIS session searches every secret in the product's globals (one per line of output).
    secret_list = sorted(s for s in secrets_seen if len(s) > 8)
    script = "\n".join(
        f'set found=0 for g="^sentai","^sentaiRun","^sentai.model.TargetD","^IRIS.Temp.sentaiTargetCred" {{ set n=g for {{ set n=$query(@n) quit:n=""  if $g(@n)["{secret}" set found=found+1 }} }} write "HITS {i} ",found,!'
        for i, secret in enumerate(secret_list))
    out = iris(PRIMARY, "IRISAPP", script)
    hits = {f"secret#{line.split()[1]}": line.split()[2] for line in out.splitlines() if line.startswith("HITS ")}
    log = subprocess.run(["docker", "exec", PRIMARY, "cat", "/usr/irissys/mgr/messages.log"], capture_output=True, text=True, env={**os.environ, "MSYS_NO_PATHCONV": "1"}).stdout
    log_hits = sum(1 for s in secrets_seen if len(s) > 8 and s in log)

    evidence = {"evidence_id": "quickstart-http", "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "stack": "docker compose: iris (SentaiTask) + iris-target (plain IRIS 2026.2)",
                "calls": calls,
                "residue": {"targetCredentialNodesAfterRuns": cred.split("CRED ")[-1].split("\n")[0].strip() if "CRED " in cred else "?",
                            "secretsFoundInProductGlobals": hits, "secretsFoundInMessagesLog": log_hits,
                            "note": "Every password and token used in this run (primary and target) was searched in ^sentai, ^sentaiRun, the target registry and ^IRIS.Temp.sentaiTargetCred, and in messages.log."}}
    text = json.dumps(evidence, indent=2, ensure_ascii=False)
    leaked = [s for s in secrets_seen if len(s) > 8 and s in text]
    assert not leaked, "a secret would be written to the evidence"
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"quickstart-http-{datetime.date.today().isoformat()}.json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text + "\n")
    summary = [(c["section"], c["note"], c["response"]["status"]) for c in calls if c["section"] not in ("setup", "poll")]
    for row in summary:
        print(*row, sep=" | ")
    print("demo run:", demo_run["state"], [(s["stepId"], s["state"], s["executedOn"]) for s in demo_run["steps"]])
    print("down run:", down_run["state"], [(s["stepId"], s["state"], s["executedOn"], s["failureReason"][:110]) for s in down_run["steps"]])
    print("residue:", evidence["residue"]["targetCredentialNodesAfterRuns"], hits, "messages.log:", log_hits)
    print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
