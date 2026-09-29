/// Spec 011: setup, seed, reset and status of a **public demo** instance. Never routed through the
/// product API (Constitution II): only the host scripts in scripts/demo call it, through
/// `iris session`. Everything that changes data refuses unless the instance is marked as a demo
/// (`^sentai("config","demo")`), which only `Setup(1)` sets.
///
/// The optional `scope` / `prefix` argument limits the work to flows whose name starts with it; the
/// unit tests use it so they never touch the instance's own flows. The host scripts pass "".
/// Every method returns an outcome value (Constitution IV):
///   {"ok": 1|0, "steps": [{"name", "ok", "detail"}], "problems": ["…"]}
Class sentai.demo.Demo Extends %RegisteredObject
{

Parameter EXAMPLENAME = "Example: storage health check";

Parameter SHOWCASENAME = "Showcase: nightly checks across servers";

Parameter TARGETNAME = "iris-target";

Parameter TARGETURL = "http://iris-target:52773";

/// Who the seed and reset save flows as.
Parameter ACTOR = "sentai-demo-setup";

ClassMethod IsDemo() As %Boolean
{
    Quit ''$G(^sentai("config", "demo"))
}

/// Marks this instance as a demo, registers the target server and seeds the two flows. `confirm`
/// must be 1: an accidental call on a normal installation changes nothing.
ClassMethod Setup(confirm As %Boolean = 0) As %DynamicObject
{
    Set out = ..Outcome()
    If 'confirm {
        Do ..Fail(out, "Setup marks this instance as a public demo; call Setup(1) to confirm")
        Quit out
    }
    Set ^sentai("config", "demo") = 1
    Do ..Step(out, "mark-demo", 1, "^sentai(""config"",""demo"") = 1")
    Do ..Merge(out, ..EnsureTarget())
    Do ..Merge(out, ..Seed())
    Quit out
}

/// Creates the example and showcase flows when missing, and restores them as shipped when they
/// were changed; leaves intact ones alone (same id, same revision).
ClassMethod Seed(prefix As %String = "") As %DynamicObject
{
    Set out = ..Outcome()
    For def = ..ExampleDefinition(), ..ShowcaseDefinition() {
        Do def.%Set("name", prefix_def.name)
        Do ..SeedOne(def, out)
    }
    Quit out
}

ClassMethod SeedOne(def As %DynamicObject, out As %DynamicObject)
{
    Set id = ""
    If '##class(sentai.model.Flow).NameIndexExists(def.name, .id) {
        Set sc = ##class(sentai.model.Flow).SaveGraph(def, "", 0, ..#ACTOR, .id)
        Do ..Step(out, "seed "_def.name, $$$ISOK(sc), $S($$$ISOK(sc):"created (id "_id_")", 1:$SYSTEM.Status.GetErrorText(sc)))
        Quit
    }
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)
    Set stored = ##class(sentai.rest.Dispatcher).ShapeFlow(flow, 1)
    If (..Fingerprint(stored) = ..Fingerprint(def)) {
        Do ..Step(out, "seed "_def.name, 1, "unchanged (id "_id_")")
        Quit
    }
    Set sc = ##class(sentai.model.Flow).SaveGraph(def, id, flow.revision, ..#ACTOR, .id)
    Do ..Step(out, "seed "_def.name, $$$ISOK(sc), $S($$$ISOK(sc):"restored as shipped (id "_id_")", 1:$SYSTEM.Status.GetErrorText(sc)))
}

/// Spec 010's example, identical to frontend/src/lib/flows/example.ts (both are compared with
/// tests/fixtures/example-flow.json).
ClassMethod ExampleDefinition() As %DynamicObject
{
    Quit {
        "name": (..#EXAMPLENAME), "defaultCategory": "Default",
        "steps": [
            {"id": "01", "type": "storage-headroom-check", "taskName": "Storage headroom check", "namespace": "%SYS", "wqmCategory": "Default", "parameters": {"minFreePercent": 10}},
            {"id": "02", "type": "db-size-report", "taskName": "Database size report", "namespace": "%SYS", "wqmCategory": "Default", "parameters": {}}
        ],
        "edges": [], "joins": [],
        "canvasGeometry": {"nodes": {"01": {"x": 40, "y": 160}, "02": {"x": 360, "y": 160}}}
    }
}

/// Data-model §5: three parallel integrity checks (two local databases, one on the target server)
/// converge on an "all must succeed" join before a database size report. Compared with
/// tests/fixtures/showcase-flow.json, which the spec 014 recorder also reads.
ClassMethod ShowcaseDefinition() As %DynamicObject
{
    Quit {
        "name": (..#SHOWCASENAME), "defaultCategory": "Default",
        "steps": [
            {"id": "01", "type": "integrity-check", "taskName": "Integrity check: USER", "namespace": "USER", "databaseDirectory": "/usr/irissys/mgr/user/", "wqmCategory": "Default", "timeoutMinutes": 30, "parameters": {}},
            {"id": "02", "type": "integrity-check", "taskName": "Integrity check: IRISAPP", "namespace": "IRISAPP", "databaseDirectory": "/data/IRISAPP_DATA/", "wqmCategory": "Default", "timeoutMinutes": 30, "parameters": {}},
            {"id": "03", "type": "integrity-check", "taskName": "Integrity check: USER on iris-target", "namespace": "USER", "target": (..#TARGETNAME), "wqmCategory": "Default", "timeoutMinutes": 30, "parameters": {}},
            {"id": "04", "type": "db-size-report", "taskName": "Database size report", "namespace": "%SYS", "wqmCategory": "Default", "timeoutMinutes": 10, "parameters": {}}
        ],
        "edges": [{"source": "01", "target": "04"}, {"source": "02", "target": "04"}, {"source": "03", "target": "04"}],
        "joins": [{"target": "04", "policy": "ALL_MUST_SUCCEED"}],
        "canvasGeometry": {"nodes": {"01": {"x": 40, "y": 60}, "02": {"x": 40, "y": 250}, "03": {"x": 40, "y": 440}, "04": {"x": 400, "y": 250}}}
    }
}

/// What makes two definitions the same flow for the seed: default category, and per step (by
/// id) type, name, namespace, directory, target, category, timeout and parameters; edges; joins.
/// Layout and revision are not part of it.
ClassMethod Fingerprint(def As %DynamicObject) As %String
{
    Kill parts
    Set parts("0") = "category="_def.defaultCategory
    Set it = def.steps.%GetIterator()
    While it.%GetNext(.k, .s) {
        Set params = $S($IsObject(s.parameters):..Canonical(s.parameters), 1:"{}")
        Set parts("s"_s.id) = $LTS($LB(s.id, s.type, s.taskName, s.namespace, s.databaseDirectory, s.target, s.wqmCategory, +s.timeoutMinutes, params), "|")
    }
    Set it = def.edges.%GetIterator()
    While it.%GetNext(.k, .e) { Set parts("e"_e.source_">"_e.target) = "" }
    Set it = def.joins.%GetIterator()
    While it.%GetNext(.k, .j) { Set parts("j"_j.target) = j.policy }
    Set key = "", out = ""
    For {
        Set key = $O(parts(key))
        Quit:(key = "")
        Set out = out_key_"="_parts(key)_";"
    }
    Quit out
}

/// Key-sorted JSON text of a flat object, so {"a":1,"b":2} and {"b":2,"a":1} compare equal.
ClassMethod Canonical(obj As %DynamicObject) As %String
{
    Kill keys
    Set it = obj.%GetIterator()
    While it.%GetNext(.k, .v) { Set keys(k) = $S($IsObject(v):v.%ToJSON(), 1:v) }
    Set k = "", out = ""
    For {
        Set k = $O(keys(k))
        Quit:(k = "")
        Set out = out_k_":"_keys(k)_","
    }
    Quit out
}

/// Registers the compose target server if missing, and sets it online. Its address is never
/// changed when it already exists (FR-012).
ClassMethod EnsureTarget() As %DynamicObject
{
    Set out = ..Outcome()
    Set target = ##class(sentai.model.Target).NameIndexOpen(..#TARGETNAME, 0)
    If '$IsObject(target) {
        Set res = ##class(sentai.targets.TargetService).Create({"name": (..#TARGETNAME), "baseUrl": (..#TARGETURL), "description": "Demo target server (compose service)"}, ..#ACTOR)
        Do ..Step(out, "register "_..#TARGETNAME, (res.httpStatus = 201), $S(res.httpStatus = 201:"registered", 1:res.problem.detail))
        Quit out
    }
    If 'target.online {
        Set res = ##class(sentai.targets.TargetService).SetOnline(..#TARGETNAME, {"online": true}, ..#ACTOR)
        Do ..Step(out, "online "_..#TARGETNAME, (res.httpStatus = 200), $S(res.httpStatus = 200:"set online", 1:res.problem.detail))
        Quit out
    }
    Do ..Step(out, "target "_..#TARGETNAME, 1, "registered and online")
    Quit out
}

/// Returns the demo to its initial state (plan D-14): removes every flow that is not one of the two
/// seeded flows, with its runs; seeds again; ensures the target; records the reset. Account
/// passwords and the alert state are handled by scripts/demo/reset.sh in %SYS.
ClassMethod Reset(scope As %String = "") As %DynamicObject
{
    Set out = ..Outcome()
    If '..IsDemo() {
        Do ..Fail(out, "not a demo instance: Reset only runs where Setup(1) was called")
        Quit out
    }
    Set flows = 0, runs = 0, problems = 0
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID AS id, name FROM sentai_model.Flow WHERE name %STARTSWITH ?", scope)
    While rs.%Next() {
        Continue:..IsSeeded(rs.%Get("name"), scope)
        Set sc = ..DeleteFlow(rs.%Get("id"), .removedRuns)
        If $$$ISOK(sc) { Set flows = flows + 1, runs = runs + removedRuns } Else { Set problems = problems + 1 Do ..Fail(out, rs.%Get("name")_": "_$SYSTEM.Status.GetErrorText(sc)) }
    }
    Do ..Step(out, "remove-visitor-flows", (problems = 0), flows_" flow"_$S(flows = 1:"", 1:"s")_", "_runs_" run"_$S(runs = 1:"", 1:"s"))
    Do ..Merge(out, ..Seed(scope))
    Do ..Merge(out, ..EnsureTarget())
    Set detail = "removed "_flows_" flow"_$S(flows = 1:"", 1:"s")_" / "_runs_" run"_$S(runs = 1:"", 1:"s")
    Set ^sentai("demo", "lastReset") = $LB($ZDATETIME($ZTIMESTAMP, 3), $S(out.ok:"ok", 1:"failed"), detail)
    Quit out
}

/// Counts for the host's status command (data-model §4).
ClassMethod Status(scope As %String = "") As %DynamicObject
{
    Set flows = 0, visitorFlows = 0, runs = 0, visitorRuns = 0
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT f.ID AS id, f.name AS name, (SELECT COUNT(*) FROM sentai_model.Run r WHERE r.flow = f.ID) AS n FROM sentai_model.Flow f WHERE f.name %STARTSWITH ?", scope)
    While rs.%Next() {
        Set flows = flows + 1
        If ..IsSeeded(rs.%Get("name"), scope) {
            Set runs = runs + rs.%Get("n")
        } Else {
            Set visitorFlows = visitorFlows + 1, visitorRuns = visitorRuns + rs.%Get("n")
        }
    }
    Set rec = $G(^sentai("demo", "lastReset"))
    Set last = $S(rec = "":{}, 1:{"at": ($LG(rec, 1)), "outcome": ($LG(rec, 2)), "detail": ($LG(rec, 3))})
    Set out = {"flows": (flows), "runs": (runs), "visitorFlows": (visitorFlows), "visitorRuns": (visitorRuns), "lastReset": (last)}
    Do out.%Set("demo", ..IsDemo(), "boolean")
    Quit out
}

ClassMethod IsSeeded(name As %String, scope As %String) As %Boolean
{
    Set upper = $ZCVT(name, "U")
    Quit (upper = $ZCVT(scope_..#EXAMPLENAME, "U")) || (upper = $ZCVT(scope_..#SHOWCASENAME, "U"))
}

/// Deletes a flow with everything that references it: its runs (step runs, log entries, run index,
/// transient credentials), edges, joins and steps. Returns the number of runs removed.
ClassMethod DeleteFlow(flowId As %String, Output removedRuns As %Integer) As %Status
{
    Set removedRuns = 0, sc = $$$OK
    TSTART
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, guid FROM sentai_model.Run WHERE flow = ?", flowId)
        While rs.%Next() {
            Set runId = rs.%Get("ID"), guid = rs.%Get("guid")
            Set srs = ##class(%SQL.Statement).%ExecDirect(, "SELECT guid FROM sentai_model.StepRun WHERE run = ?", runId)
            While srs.%Next() { Kill ^sentaiRun("idx", srs.%Get("guid")) }
            &sql(DELETE FROM sentai_model.StepRun WHERE run = :runId)
            &sql(DELETE FROM sentai_model.LogEntry WHERE run = :runId)
            &sql(DELETE FROM sentai_model.Run WHERE ID = :runId)
            Kill:(guid '= "") ^sentaiRun(guid), ^IRIS.Temp.sentaiTargetCred(guid)
            Set removedRuns = removedRuns + 1
        }
        &sql(DELETE FROM sentai_model.Edge WHERE flow = :flowId)
        // "Join" is an SQL reserved word: unquoted, this delete failed and the flow could not go.
        &sql(DELETE FROM sentai_model."Join" WHERE flow = :flowId)
        &sql(DELETE FROM sentai_model.Step WHERE flow = :flowId)
        $$$ThrowOnError(##class(sentai.model.Flow).%DeleteId(flowId))
        TCOMMIT
    }
    Catch ex {
        TROLLBACK 1
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// --- outcome value helpers ---
ClassMethod Outcome() As %DynamicObject
{
    Set out = {"steps": [], "problems": []}
    Do out.%Set("ok", 1, "boolean")
    Quit out
}

ClassMethod Step(out As %DynamicObject, name As %String, ok As %Boolean, detail As %String)
{
    Set step = {"name": (name), "detail": (detail)}
    Do step.%Set("ok", ''ok, "boolean")
    Do out.steps.%Push(step)
    If 'ok {
        Do out.%Set("ok", 0, "boolean")
        Do out.problems.%Push(name_": "_detail)
    }
}

ClassMethod Fail(out As %DynamicObject, problem As %String)
{
    Do out.%Set("ok", 0, "boolean")
    Do out.problems.%Push(problem)
}

ClassMethod Merge(out As %DynamicObject, other As %DynamicObject)
{
    Set it = other.steps.%GetIterator()
    While it.%GetNext(.k, .s) { Do out.steps.%Push(s) }
    Set it = other.problems.%GetIterator()
    While it.%GetNext(.k, .p) { Do out.problems.%Push(p) }
    Do:'other.ok out.%Set("ok", 0, "boolean")
}

}
