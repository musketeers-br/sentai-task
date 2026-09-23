#!/usr/bin/env python3
"""Spec 004 quickstart (a)-(c) over HTTP against the real instance.

Credentials come from the environment only (never stored, never written to the evidence file):
    IRIS_USER=... IRIS_PASSWORD=... python3 specs/004-backend-hardening/evidence/run_quickstart.py

Writes specs/004-backend-hardening/evidence/quickstart-http-<date>.json (status + body per call)
and prints a PASS/FAIL line per expectation. Exit code 0 only when every expectation holds.
"""
import base64
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.request

HOST = os.environ.get("IRIS_BASE", "http://localhost:52773")
API = HOST + "/csp/sentai/api/v1"
USER = os.environ.get("IRIS_USER")
PASSWORD = os.environ.get("IRIS_PASSWORD")
STAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "quickstart-http-%s.json" % STAMP[:8])

# Default database directories of the namespaces used, as on the T070 instance.
DIRS = {"USER": "/usr/irissys/mgr/user/", "IRISAPP": "/data/IRISAPP_DATA/", "%SYS": "/usr/irissys/mgr/"}

record = {"instance": HOST, "startedAt": STAMP, "calls": [], "expectations": []}
failures = 0


def call(method, path, token=None, body=None, label=""):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            status, text = resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        status, text = e.code, e.read().decode()
    try:
        parsed = json.loads(text) if text else None
    except ValueError:
        parsed = text
    record["calls"].append({"label": label, "method": method, "path": path, "status": status, "body": parsed})
    return status, parsed


def login():
    req = urllib.request.Request(HOST + "/api/admin/login", data=b"", method="POST")
    req.add_header("Authorization", "Basic " + base64.b64encode(("%s:%s" % (USER, PASSWORD)).encode()).decode())
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())["access_token"]


def expect(label, ok, detail=""):
    global failures
    record["expectations"].append({"label": label, "pass": bool(ok), "detail": detail})
    print("%s  %s %s" % ("PASS" if ok else "FAIL", label, detail))
    if not ok:
        failures += 1


def codes(report):
    return [e.get("code") for e in (report or {}).get("errors", [])]


def step(sid, ns, category="Default", type_="integrity-check"):
    s = {"id": sid, "type": type_, "taskName": "%s %s" % (type_, sid), "namespace": ns,
         "runAsUser": "irisadm", "timeoutMinutes": 30, "wqmCategory": category}
    if type_ == "integrity-check":
        s["databaseDirectory"] = DIRS[ns]
    return s


def flow(name, steps, edges=(), joins=()):
    return {"schemaVersion": 1, "name": "%s-%s" % (name, STAMP), "defaultCategory": "Default",
            "steps": steps, "edges": list(edges), "joins": list(joins)}


def sse_until_terminal(token, guid, limit_s=55):
    """Reads the run's SSE stream until run-terminal (or limit). Returns the event names seen."""
    req = urllib.request.Request(API + "/runs/%s/events" % guid)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "text/event-stream")
    events, t0 = [], time.time()
    try:
        with urllib.request.urlopen(req, timeout=limit_s) as resp:
            for raw in resp:
                line = raw.decode().strip()
                if line.startswith("event:"):
                    events.append({"event": line[6:].strip(), "t": round(time.time() - t0, 1)})
                    if events[-1]["event"] == "run-terminal":
                        break
                if time.time() - t0 > limit_s:
                    break
    except Exception as e:  # timeout or disconnect: recorded, judged by the final GET
        events.append({"event": "stream-ended", "detail": repr(e), "t": round(time.time() - t0, 1)})
    record["calls"].append({"label": "(a) SSE", "method": "GET", "path": "/runs/%s/events" % guid, "events": events})
    return [e["event"] for e in events]


def main():
    if not USER or not PASSWORD:
        sys.exit("Set IRIS_USER and IRIS_PASSWORD in the environment.")

    # Catalog: availability per type (FR-001)
    tok = login()
    st, cat = call("GET", "/catalog/step-types", tok, label="catalog")
    avail = {e["type"]: e.get("available") for e in (cat or [])}
    expect("catalog: only integrity-check available", st == 200 and avail.get("integrity-check") is True
           and all(v is False for k, v in avail.items() if k != "integrity-check") and len(avail) == 7, str(avail))

    # (a) 3 integrity-check steps, fan-out/fan-in on Default -> validate -> dispatch -> SSE -> completed
    tok = login()
    st, created = call("POST", "/flows", tok, flow("QS004-a", [step("01", "USER"), step("02", "IRISAPP"), step("03", "%SYS")],
                                                  edges=[{"source": "01", "target": "03"}, {"source": "02", "target": "03"}],
                                                  joins=[{"target": "03", "policy": "ALL_MUST_SUCCEED"}]), "(a) create")
    expect("(a) create 201", st == 201, str(st))
    fid = (created or {}).get("id")
    st, rep = call("POST", "/flows/%s/validate" % fid, tok, {}, "(a) validate")
    expect("(a) validate errors: []", st == 200 and codes(rep) == [], str(codes(rep)))
    st, run = call("POST", "/flows/%s/dispatch" % fid, tok, {"confirmations": []}, "(a) dispatch")
    expect("(a) dispatch 202", st == 202, str(st))
    guid = (run or {}).get("guid")
    if guid:
        events = sse_until_terminal(tok, guid)
        expect("(a) SSE reached run-terminal", "run-terminal" in events, str(events[-3:]))
        tok = login()
        st, final = call("GET", "/runs/%s" % guid, tok, label="(a) final run")
        steps = {s.get("stepId"): s.get("state") for s in (final or {}).get("steps", [])}
        reasons = [s.get("failureReason") for s in (final or {}).get("steps", []) if s.get("failureReason")]
        expect("(a) run completed, all 3 steps completed", (final or {}).get("state") == "completed"
               and steps == {"01": "completed", "02": "completed", "03": "completed"}, "%s %s" % ((final or {}).get("state"), steps))
        expect("(a) no 404 in any failure reason", not any("404" in r for r in reasons), str(reasons))

    # (b) unsupported type refused
    tok = login()
    st, created = call("POST", "/flows", tok, flow("QS004-b", [step("01", "%SYS", type_="compact-globals")]), "(b) create")
    expect("(b) create 201 (flow stays loadable)", st == 201, str(st))
    fid = (created or {}).get("id")
    st, rep = call("POST", "/flows/%s/validate" % fid, tok, {}, "(b) validate")
    expect("(b) validate reports STEP_TYPE_NOT_SUPPORTED_ON_TARGET", codes(rep) == ["STEP_TYPE_NOT_SUPPORTED_ON_TARGET"], str(codes(rep)))
    st, rep = call("POST", "/flows/%s/dispatch" % fid, tok, {"confirmations": []}, "(b) dispatch")
    expect("(b) dispatch 422 with the same error", st == 422 and "STEP_TYPE_NOT_SUPPORTED_ON_TARGET" in codes(rep), "%s %s" % (st, codes(rep)))

    # (c) unknown category refused
    tok = login()
    st, created = call("POST", "/flows", tok, flow("QS004-c", [step("01", "USER", category="NONEXISTENT")]), "(c) create")
    expect("(c) create 201", st == 201, str(st))
    fid = (created or {}).get("id")
    st, rep = call("POST", "/flows/%s/validate" % fid, tok, {}, "(c) validate")
    expect("(c) validate reports CATEGORY_NOT_FOUND", codes(rep) == ["CATEGORY_NOT_FOUND"], str(codes(rep)))
    st, rep = call("POST", "/flows/%s/dispatch" % fid, tok, {"confirmations": []}, "(c) dispatch")
    expect("(c) dispatch 422 with the same error", st == 422 and "CATEGORY_NOT_FOUND" in codes(rep), "%s %s" % (st, codes(rep)))

    record["failures"] = failures
    with open(OUT, "w") as f:
        json.dump(record, f, indent=2)
    print("\n%d failure(s). Evidence: %s" % (failures, OUT))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
