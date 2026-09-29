"""Spec 011 acceptance of the public demo stack (quickstart A) and of the README (--readme).

Run against an isolated demo project, never the dev stack:
    COMPOSE_PROJECT_NAME=sentai-demo-check DEMO_HTTP_PORT=8080 DEMO_HTTPS_PORT=8443 \
      python3 scripts/demo/acceptance.py --base http://localhost:8080 --env-file .env.demo-check
    python3 scripts/demo/acceptance.py --readme

Prints PASS/FAIL per check and exits 1 on any failure. The privileged secret is read from the env
file only to check that it works; it is never printed.
"""
import argparse, base64, json, os, pathlib, re, shutil, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

REPO = pathlib.Path(__file__).resolve().parents[2]
DEMO = ("sentai-demo", "sentai-demo-2026")
SHOWCASE = "Showcase: nightly checks across servers"
results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(("PASS " if ok else "FAIL ") + name + (f" — {detail}" if detail else ""), flush=True)


def call(base, method, path, body=None, auth=None):
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["Authorization"] = auth
    req = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(), method=method, headers=headers)
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req, timeout=60) as r:
            text = r.read().decode()
            return r.status, parse(text)
    except urllib.error.HTTPError as e:
        return e.code, parse(e.read().decode())


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def parse(text):
    try:
        return json.loads(text)
    except ValueError:
        return text


def basic(user, password):
    return "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()


def login(base, user, password):
    s, b = call(base, "POST", "/api/admin/login", {}, basic(user, password))
    return s, (b if isinstance(b, dict) else {})


def env_file_values(path):
    values = {}
    for line in pathlib.Path(path).read_text().splitlines():
        m = re.match(r"^\s*([A-Z_]+)\s*=\s*(.*)$", line)
        if m:
            values[m.group(1)] = m.group(2).strip().strip('"')
    return values


def bash_path():
    """On Windows, a plain "bash" is WSL's; the scripts need Git Bash (or SENTAI_BASH)."""
    if os.environ.get("SENTAI_BASH"):
        return os.environ["SENTAI_BASH"]
    if os.name == "nt":
        for candidate in (r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files (x86)\Git\bin\bash.exe"):
            if os.path.exists(candidate):
                return candidate
    return shutil.which("bash") or "bash"


def bash(script, *args, env=None):
    return subprocess.run([bash_path(), str(REPO / "scripts/demo" / script), *args], cwd=REPO, capture_output=True, text=True,
                          env={**os.environ, "MSYS_NO_PATHCONV": "1", **(env or {})})


def compose_container(service):
    out = subprocess.run(["docker", "compose", "-f", "docker-compose.yml", "-f", "docker-compose.demo.yml", "ps", "-q", service],
                         cwd=REPO, capture_output=True, text=True).stdout.strip()
    return out.splitlines()[0] if out else ""


def target_login(password):
    """Signs in to iris-target from inside the compose network (it has no host port)."""
    code = ("import base64,sys,urllib.request,urllib.error\n"
            "pw=sys.stdin.read()\n"
            "r=urllib.request.Request('http://iris-target:52773/api/admin/login',data=b'{}',method='POST',"
            "headers={'Content-Type':'application/json','Authorization':'Basic '+base64.b64encode(('_SYSTEM:'+pw).encode()).decode()})\n"
            "try: print(urllib.request.urlopen(r,timeout=20).status)\n"
            "except urllib.error.HTTPError as e: print(e.code)\n")
    out = subprocess.run(["docker", "exec", "-i", compose_container("iris"), "python3", "-c", code], input=password,
                         capture_output=True, text=True, env={**os.environ, "MSYS_NO_PATHCONV": "1"}).stdout.strip()
    return out


def run_showcase(base, target_password):
    a = login(base, *DEMO)[1].get("access_token")
    A = "Bearer " + a
    s, flows = call(base, "GET", "/csp/sentai/api/v1/flows", auth=A)
    showcase = [f for f in flows if isinstance(flows, list) and f["name"] == SHOWCASE] if s == 200 else []
    check("showcase flow exists", len(showcase) == 1, f"HTTP {s}")
    if not showcase:
        return
    fid = showcase[0]["id"]
    s, rep = call(base, "POST", f"/csp/sentai/api/v1/flows/{fid}/validate", {}, A)
    check("showcase validates with 0 errors as the demo account", s == 200 and rep.get("errors") == [], json.dumps(rep)[:300])
    ra, rr = (lambda b: (b.get("access_token"), b.get("refresh_token")))(login(base, *DEMO)[1])
    s, pair = call(base, "POST", "/csp/sentai/api/v1/targets/iris-target/sign-in", {"user": DEMO[0], "password": target_password}, "Bearer " + ra)
    check("demo account signs in to iris-target through the primary", s == 200, f"HTTP {s}")
    body = {"confirmations": [], "runCredential": {"refreshToken": rr},
            "targetCredentials": [{"target": "iris-target", "refreshToken": pair.get("refreshToken", "")}]}
    s, run = call(base, "POST", f"/csp/sentai/api/v1/flows/{fid}/dispatch", body, "Bearer " + ra)
    check("showcase dispatched", s == 202, f"HTTP {s} {'' if s == 202 else json.dumps(run)[:300]}")
    if s != 202:
        return
    started, final = time.time(), {}
    while time.time() - started < 300:
        a = login(base, *DEMO)[1].get("access_token")
        s, final = call(base, "GET", f"/csp/sentai/api/v1/runs/{run['guid']}", auth="Bearer " + a)
        if s == 200 and final.get("state") != "running":
            break
        time.sleep(3)
    where = {x["stepId"]: (x["state"], x.get("executedOn")) for x in final.get("steps", [])}
    check("showcase completes; step 03 ran on iris-target", final.get("state") == "completed" and where.get("03") == ("completed", "iris-target"),
          f"{final.get('state')} in {int(time.time() - started)} s {where}")


def visitor_flow_run_and_cancel(base, secret):
    """A visitor flow whose integrity check is cancelled while running: the platform raises an alert."""
    a = login(base, *DEMO)[1].get("access_token")
    flow = {"name": f"visitor {int(time.time())}", "defaultCategory": "Default", "edges": [], "joins": [], "steps": [
        {"id": "01", "type": "integrity-check", "taskName": "visitor check", "namespace": "USER",
         "databaseDirectory": "/usr/irissys/mgr/user/", "wqmCategory": "Default", "timeoutMinutes": 30}]}
    s, f = call(base, "POST", "/csp/sentai/api/v1/flows", flow, "Bearer " + a)
    ra, rr = (lambda b: (b.get("access_token"), b.get("refresh_token")))(login(base, *DEMO)[1])
    s, run = call(base, "POST", f"/csp/sentai/api/v1/flows/{f['id']}/dispatch", {"confirmations": [], "runCredential": {"refreshToken": rr}}, "Bearer " + ra)
    for _ in range(20):
        a = login(base, *DEMO)[1].get("access_token")
        s, r = call(base, "GET", f"/csp/sentai/api/v1/runs/{run['guid']}", auth="Bearer " + a)
        if any(x["state"] == "running" for x in r.get("steps", [])):
            break
        time.sleep(1)
    s, _ = call(base, "POST", f"/csp/sentai/api/v1/runs/{run['guid']}/cancel", {}, "Bearer " + a)
    return s


def demo_checks(base, env_file):
    env = env_file_values(env_file)
    secret = env.get("SENTAI_DEMO_SECRET", "")

    # 1. No secret → refused before anything starts (a throwaway project name proves "nothing").
    empty = REPO / ".env.demo-nosecret"
    empty.write_text("DEMO_HTTP_PORT=8099\n")
    try:
        p = bash("up.sh", "--env-file", str(empty), env={"COMPOSE_PROJECT_NAME": "sentai-demo-nosecret"})
        started = subprocess.run(["docker", "compose", "-p", "sentai-demo-nosecret", "ps", "-q"], cwd=REPO, capture_output=True, text=True).stdout.strip()
        check("up.sh without SENTAI_DEMO_SECRET refuses and starts nothing", p.returncode != 0 and "SENTAI_DEMO_SECRET" in p.stderr and not started,
              f"exit {p.returncode}")
    finally:
        empty.unlink(missing_ok=True)

    # 2. Only the canvas and /api/admin are forwarded.
    s, _ = call(base, "GET", "/")
    check("/ redirects to the canvas", s in (301, 302, 308), f"HTTP {s}")
    s, _ = call(base, "GET", "/csp/sentai/")
    check("canvas answers", s == 200, f"HTTP {s}")
    for path in ("/csp/sys/UtilHome.csp", "/api/atelier/", "/api/mgmnt/", "/_vscode/", "/csp/user/"):
        s, _ = call(base, "GET", path)
        check(f"{path} is not reachable", s == 404, f"HTTP {s}")

    # 3. The default privileged password is refused on both instances; the secret works.
    check("_SYSTEM:SYS refused on the primary", login(base, "_SYSTEM", "SYS")[0] == 401)
    check("the secret signs _SYSTEM in on the primary", login(base, "_SYSTEM", secret)[0] == 200)
    check("_SYSTEM:SYS refused on iris-target", target_login("SYS") == "401")

    # 4. The demo account works and holds no security administration.
    s, b = login(base, *DEMO)
    check("demo account signs in", s == 200, f"HTTP {s}")
    s, _ = call(base, "GET", "/api/admin/v2/security/users", auth="Bearer " + b.get("access_token", ""))
    check("demo account cannot read platform users (no security administration)", s == 403, f"HTTP {s}")

    # 5. The showcase runs to the end as the demo account.
    run_showcase(base, DEMO[1])

    # 6. The sign-in hint file.
    s, info = call(base, "GET", "/csp/sentai/demo.json")
    check("demo.json is served with the demo account and showcase", s == 200 and isinstance(info, dict)
          and info.get("account") == DEMO[0] and info.get("showcase") == SHOWCASE, f"HTTP {s}")

    # 7. A visitor leaves a flow, a run and an alert; the reset returns everything to the start.
    visitor_flow_run_and_cancel(base, secret)
    time.sleep(5)
    st = bash("status.sh", "--env-file", env_file)
    counts = status_counts(st.stdout)
    check("status reports the visitor flow and its run", counts.get("visitorFlows", 0) >= 1 and counts.get("visitorRuns", 0) >= 1,
          st.stdout.strip().splitlines()[-1] if st.stdout else st.stderr)
    r = bash("reset.sh", "--env-file", env_file)
    check("reset succeeds", r.returncode == 0, r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr[-300:])
    st = bash("status.sh", "--env-file", env_file)
    check("after reset: 0 visitor flows and runs, no alert, all healthy (exit 0)",
          st.returncode == 0 and '"visitorFlows":0' in st.stdout and '"visitorRuns":0' in st.stdout and "alert state: 0" in st.stdout,
          " | ".join(st.stdout.strip().splitlines()))
    check("after reset: _SYSTEM:SYS still refused, demo account still signs in",
          login(base, "_SYSTEM", "SYS")[0] == 401 and login(base, *DEMO)[0] == 200)

    # 8. A restart keeps the securing and the account.
    subprocess.run(["docker", "compose", "-f", "docker-compose.yml", "-f", "docker-compose.demo.yml", "restart"], cwd=REPO, capture_output=True)
    for _ in range(60):
        s, _ = call(base, "GET", "/csp/sentai/")
        if s == 200 and login(base, *DEMO)[0] == 200:
            break
        time.sleep(5)
    check("after restart: _SYSTEM:SYS refused, demo account signs in",
          login(base, "_SYSTEM", "SYS")[0] == 401 and login(base, *DEMO)[0] == 200)


def status_counts(text):
    m = re.search(r"^demo: (\{.*\})\s*$", text, re.M)
    try:
        return json.loads(m.group(1)) if m else {}
    except ValueError:
        return {}


def readme_checks():
    text = (REPO / "README.md").read_text(encoding="utf-8")
    headings = [m.group(0) for m in re.finditer(r"^#{1,6} .+$", text, re.M)]
    order = [i for i, h in enumerate(headings) if re.search(r"SentaiTask 戦隊|Try it|Contest areas covered|Motivation", h)]
    names = [headings[i] for i in order]
    wanted = ["SentaiTask 戦隊", "Try it", "Contest areas covered", "Motivation"]
    got = [next((w for w in wanted if w in n), n) for n in names]
    check("README order: title → Try it → Contest areas → Motivation", got[:4] == wanted, " → ".join(got))
    title_at = text.find("# 🦸 SentaiTask")
    picture = re.search(r"!\[[^\]]+\]\((assets/[^)]+)\)|<img[^>]+src=\"\./?(assets/[^\"]+)\"", text[title_at:text.find("Try it")] if title_at >= 0 else "")
    check("a product picture sits between the title and Try it", bool(picture))
    try_block = text[text.find("Try it"):text.find("### Contest areas covered")]
    table = text[text.find("### Contest areas covered"):text.find("## 🌌 Motivation")]
    check("Try it names the demo account and a local quickstart", "sentai-demo" in try_block and "docker compose up" in try_block)
    anchors = {slug(h) for h in headings}
    bad = []
    for link in re.findall(r"\]\(([^)\s]+)\)", try_block + table):
        if link.startswith(("http://", "https://")):
            continue
        if link.startswith("#"):
            if urllib.parse.unquote(link[1:]) not in anchors:
                bad.append(link)
        elif not (REPO / link.split("#")[0]).exists():
            bad.append(link)
    check("every relative link in Try it and the area table resolves", not bad, ", ".join(bad))


def slug(heading):
    """GitHub's anchor: lower case, punctuation and symbols dropped (emoji too), the emoji
    variation selector U+FE0F kept, spaces to hyphens."""
    h = re.sub(r"^#+\s*", "", heading).strip().lower()
    h = re.sub(r"[^\w\- \uFE0F]", "", h)
    return h.replace(" ", "-")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")  # Windows consoles default to cp1252
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://localhost:8080")
    ap.add_argument("--env-file", default=".env")
    ap.add_argument("--readme", action="store_true")
    args = ap.parse_args()
    if args.readme:
        readme_checks()
    else:
        demo_checks(args.base, args.env_file)
    print(f"\n{sum(results)}/{len(results)} checks passed")
    sys.exit(0 if all(results) else 1)
