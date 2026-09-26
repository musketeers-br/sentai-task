/// The sole HTTP entry point (%CSP.REST). Routing, authentication (OnPreDispatch), JSON
/// (de)serialization, and error-to-HTTP-status translation only — no business logic lives
/// here; every method immediately delegates to an application-layer service class
/// (research.md R-001). Implements exactly the surface of
/// specs/002-canvas-ui/contracts/openapi.yaml — see
/// specs/003-backend-objectscript/contracts/rest-mapping.md for the endpoint -> class map.
Class sentai.rest.Dispatcher Extends %CSP.REST
{

Parameter HandleCorsRequest = 1;

/// Browsers send UTF-8 JSON; without these, request bodies are read as Latin-1 and any
/// non-ASCII text (e.g. "—", "ção") is persisted as mojibake.
Parameter CHARSET = "utf-8";

Parameter CONVERTINPUTSTREAM = 1;

/// No "Unauthenticated" option (HANDOFF constraint, FR-040); a dedicated role
/// (%SENTAI_Operator, proposed) is required at the CSP-application level, configured
/// separately from this class (Security.Applications), not here — this class enforces
/// token validity per request, never relying on session caching (FR-041, Constitution III).
Parameter UseSession = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
    <Route Url="/flows" Method="GET" Call="ListFlows"/>
    <Route Url="/flows" Method="POST" Call="CreateFlow"/>
    <Route Url="/flows/:flowId" Method="GET" Call="ReadFlow"/>
    <Route Url="/flows/:flowId" Method="PUT" Call="SaveFlow"/>
    <Route Url="/flows/:flowId/validate" Method="POST" Call="ValidateFlow"/>
    <Route Url="/flows/:flowId/schedule" Method="POST" Call="ScheduleFlow"/>
    <Route Url="/flows/:flowId/dispatch" Method="POST" Call="DispatchFlow"/>
    <Route Url="/runs" Method="GET" Call="ListRuns"/>
    <Route Url="/runs/:runGuid" Method="GET" Call="ReadRun"/>
    <Route Url="/runs/:runGuid/events" Method="GET" Call="StreamEvents"/>
    <Route Url="/runs/:runGuid/cancel" Method="POST" Call="CancelRun"/>
    <Route Url="/runs/:runGuid/pause" Method="POST" Call="PauseRun"/>
    <Route Url="/runs/:runGuid/steps/:stepGuid/cancel" Method="POST" Call="CancelStep"/>
    <Route Url="/runs/:runGuid/steps/:stepGuid/pause" Method="POST" Call="PauseStep"/>
    <Route Url="/runs/:runGuid/steps/:stepGuid/rerun" Method="POST" Call="RerunStep"/>
    <Route Url="/catalog/step-types" Method="GET" Call="ListStepTypes"/>
    <Route Url="/catalog/tasks" Method="GET" Call="ListCatalogTasks"/>
    <Route Url="/catalog/tasks/:taskId" Method="GET" Call="ReadCatalogTask"/>
    <Route Url="/catalog/tasks/:taskId/suspend" Method="POST" Call="SuspendCatalogTask"/>
    <Route Url="/wqm/categories" Method="GET" Call="ListWqmCategories"/>
    <Route Url="/wqm/categories/:name" Method="GET" Call="ReadWqmCategory"/>
    <Route Url="/wqm/categories/:name" Method="PUT" Call="WriteWqmCategory"/>
</Routes>
}

/// --- Authentication (FR-040, FR-041, NFR-006, research.md R-002) ---
/// Validates the same 60-second Bearer access token the administrative API uses, on
/// every request, with no caching or reuse of the authorization decision across requests
/// (Constitution III). Native validation is attempted first; if no native mechanism is
/// confirmed available on the target instance, falls back to an internal
/// `GET /api/admin/info` call, treating HTTP 200 as proof of validity (research.md R-002
/// documented fallback — flagged as an open risk, plan.md OQ-01).
ClassMethod OnPreDispatch(pUrl As %String, pMethod As %String, ByRef pContinue As %Boolean) As %Status
{
    Set pContinue = 0
    Set token = ..ExtractBearerToken()
    If (token = "") {
        Do ..WriteProblem(401, "Unauthorized", "Missing or malformed Authorization header")
        Quit $$$OK
    }

    If '..IsTokenValid(token) {
        Do ..WriteProblem(401, "Unauthorized", "Invalid or expired token")
        Quit $$$OK
    }

    // Stash the token for this request only — read by the route methods below, never
    // persisted or reused across requests (FR-041).
    Set %session("sentai.bearerToken") = token
    Set pContinue = 1
    Quit $$$OK
}

ClassMethod ExtractBearerToken() As %String
{
    Set header = %request.GetCgiEnv("HTTP_AUTHORIZATION")
    If (header = "") Quit ""
    If ($EXTRACT(header, 1, 7) '= "Bearer ") Quit ""
    Quit $EXTRACT(header, 8, *)
}

/// research.md R-002 fallback: an internal, same-instance call to the administrative
/// API's own info endpoint — at the cost of one extra HTTP call per request, pending
/// confirmation of a cheaper native mechanism against a real instance (OQ-01).
/// 200 and 403 both prove the token authenticated: 403 is the platform refusing that operator
/// the administrative read, not the token (an invalid or expired token is 401; spec 006
/// evidence d). This is an authentication check only; what the operator may do is decided by
/// the platform at each call, and the platform's refusal reaches the operator verbatim
/// (Constitution III). Any other answer is not proof.
ClassMethod IsTokenValid(token As %String) As %Boolean
{
    Set httpStatus = 0, location = ""
    Do ##class(sentai.dispatch.AdminApiClient).Get("/api/admin/info", token, .httpStatus, .location)
    Quit (httpStatus = 200) || (httpStatus = 403)
}

ClassMethod CurrentToken() As %String
{
    Quit $G(%session("sentai.bearerToken"))
}

ClassMethod CurrentUser() As %String
{
    Quit $G(%session("Username"), $USERNAME)
}

/// The platform's own words for a refused call: its status summary, else its body, else the
/// HTTP status (Constitution III: never paraphrased).
ClassMethod PlatformText(body, httpStatus As %Integer) As %String
{
    If $IsObject(body) {
        If $IsObject(body."status") && (body."status"."summary" '= "") Quit body."status"."summary"
        Set text = body.%ToJSON()
        Quit:(text '= "{}") text
    }
    Quit "The platform refused the run credential (HTTP "_httpStatus_")"
}

/// --- Response helpers (contracts/rest-mapping.md §Errors) ---
ClassMethod WriteJSON(status As %Integer, obj) As %Status
{
    Set %response.Status = status
    Set %response.ContentType = "application/json"
    If $IsObject(obj) {
        Write obj.%ToJSON()
    } Else {
        Write "{}"
    }
    Quit $$$OK
}

/// Writes a service outcome as it is: `{httpStatus, body}` or `{httpStatus, problem}`, where the
/// problem keeps the platform's `platformStatus`/`platformInfo` untouched (Constitution III, IV).
ClassMethod WriteOutcome(outcome As %DynamicObject) As %Status
{
    If outcome.%IsDefined("problem") Quit ..WriteJSON(outcome.httpStatus, outcome.problem)
    Quit ..WriteJSON(outcome.httpStatus, outcome.body)
}

ClassMethod WriteProblem(status As %Integer, title As %String, detail As %String) As %Status
{
    Set problem = {}
    Do problem.%Set("status", status)
    Do problem.%Set("title", title)
    Do problem.%Set("detail", detail)
    Quit ..WriteJSON(status, problem)
}

/// --- /flows (FR-001–FR-007, User Story 1) ---
ClassMethod ListFlows() As %Status
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT %ID AS rowId, name, revision, savedAt, savedBy, scheduleSpec FROM sentai_model.Flow ORDER BY name")
    Set result = rs.%Execute()
    While result.%Next() {
        Set item = {}
        Do item.%Set("id", result.%Get("rowId"))
        Do item.%Set("name", result.%Get("name"))
        Do item.%Set("revision", result.%Get("revision"))
        Do item.%Set("savedAt", result.%Get("savedAt"))
        Do item.%Set("savedBy", result.%Get("savedBy"))
        Do item.%Set("nextRun", $S(result.%Get("scheduleSpec") '= "":result.%Get("scheduleSpec"), 1:$$$NULLOREF))
        Do out.%Push(item)
    }
    Quit ..WriteJSON(200, out)
}

ClassMethod CreateFlow() As %Status
{
    Set payload = ..ReadJSONBody()
    Set structural = ..ValidateStructural(payload)
    If '##class(sentai.validation.FlowValidator).HasNoErrors(structural) {
        Quit ..WriteJSON(422, structural)
    }

    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, ..CurrentUser(), .newId)
    If $$$ISERR(sc) {
        Quit ..TranslateSaveError(sc)
    }

    Set flow = ##class(sentai.model.Flow).%OpenId(newId, 0)
    Quit ..WriteJSON(201, ..ShapeFlow(flow, 1))
}

ClassMethod ReadFlow(flowId As %String) As %Status
{
    Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 0, .sc)
    If $$$ISERR(sc) Quit ..WriteProblem(404, "Not Found", "Flow '"_flowId_"' does not exist")
    Quit ..WriteJSON(200, ..ShapeFlow(flow, 1))
}

ClassMethod SaveFlow(flowId As %String) As %Status
{
    Set payload = ..ReadJSONBody()
    Set expectedRevision = +%request.Get("revision")
    If (expectedRevision = 0) {
        Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 0, .sc)
        If $$$ISOK(sc) Set expectedRevision = flow.revision
    }

    Set structural = ..ValidateStructural(payload)
    If '##class(sentai.validation.FlowValidator).HasNoErrors(structural) {
        Quit ..WriteJSON(422, structural)
    }

    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, flowId, expectedRevision, ..CurrentUser(), .savedId)
    If $$$ISERR(sc) {
        Quit ..TranslateSaveError(sc)
    }

    Set flow = ##class(sentai.model.Flow).%OpenId(savedId, 0)
    Quit ..WriteJSON(200, ..ShapeFlow(flow, 1))
}

/// Minimal structural precondition shared by create/save (required fields + acyclicity of
/// the SUBMITTED payload, before anything is persisted) — the full rule set (namespace,
/// per-type schema, WQM invariant, mount precondition) is FlowValidator's job on the
/// ALREADY-PERSISTED flow via /validate and /dispatch (FR-007, FR-012).
ClassMethod ValidateStructural(payload As %DynamicObject) As %DynamicObject
{
    Set errors = [], warnings = []
    If '$IsObject(payload) || (payload.name = "") {
        Do errors.%Push({"stepId": "", "code": "MISSING_NAME", "message": "name is required"})
    }
    If $IsObject(payload) && payload.%IsDefined("edges") {
        If ##class(sentai.model.Edge).WouldGraphBeCyclic("", payload."edges") {
            Do errors.%Push({"stepId": "", "code": "CYCLE_DETECTED", "message": "The submitted edge set contains a cycle"})
        }
    }
    Quit ##class(sentai.validation.FlowValidator).Report(errors, warnings)
}

ClassMethod TranslateSaveError(sc As %Status) As %Status
{
    Set text = $SYSTEM.Status.GetErrorText(sc)
    Return:(text [ "SentaiNameConflict") ..WriteProblem(409, "Conflict", "A flow with this name already exists")
    Return:(text [ "SentaiStaleRevision") ..WriteProblem(409, "Conflict", "Flow was saved by someone else since it was loaded")
    Return:(text [ "SentaiCycle") ..WriteJSON(422, ##class(sentai.validation.FlowValidator).Report([{"stepId": "", "code": "CYCLE_DETECTED", "message": (text)}], []))
    Return ..WriteProblem(500, "Internal Error", text)
}

ClassMethod ShapeFlow(flow As sentai.model.Flow, includeGraph As %Boolean) As %DynamicObject
{
    Set out = {}
    Do out.%Set("id", flow.%Id())
    Do out.%Set("name", flow.name)
    Do out.%Set("revision", flow.revision)
    Do out.%Set("savedAt", flow.savedAt)
    Do out.%Set("savedBy", flow.savedBy)
    Do out.%Set("defaultCategory", flow.defaultCategory)
    Quit:'includeGraph out

    Set steps = []
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT %ID AS rowId, id, type, taskName, namespace, databaseDirectory, runAsUser, timeoutMinutes, wqmCategory, customClass FROM sentai_model.Step WHERE flow = ?")
    Set result = rs.%Execute(flow.%Id())
    While result.%Next() {
        Set s = {}
        Do s.%Set("id", result.%Get("id"))
        Do s.%Set("type", result.%Get("type"))
        Do s.%Set("taskName", result.%Get("taskName"))
        Do s.%Set("namespace", result.%Get("namespace"))
        Do s.%Set("databaseDirectory", result.%Get("databaseDirectory"))
        Do s.%Set("runAsUser", result.%Get("runAsUser"))
        Do s.%Set("timeoutMinutes", result.%Get("timeoutMinutes"))
        Do s.%Set("wqmCategory", result.%Get("wqmCategory"))
        Do s.%Set("customClass", result.%Get("customClass"))
        // %DynamicObject properties are not SQL-projected; read parameters from the object.
        Set stepObj = ##class(sentai.model.Step).%OpenId(result.%Get("rowId"), 0)
        Do s.%Set("parameters", $S($IsObject(stepObj) && $IsObject(stepObj.parameters):stepObj.parameters, 1:{}))
        Do s.%Set("isDestructive", ##class(sentai.registry.StepType).IsDestructive(result.%Get("type")))
        Do steps.%Push(s)
    }
    Do out.%Set("steps", steps)

    Set edges = []
    Set rs2 = ##class(%SQL.Statement).%New()
    Do rs2.%Prepare("SELECT source, target FROM sentai_model.Edge WHERE flow = ?")
    Set result2 = rs2.%Execute(flow.%Id())
    While result2.%Next() {
        Do edges.%Push({"source": (result2.%Get("source")), "target": (result2.%Get("target"))})
    }
    Do out.%Set("edges", edges)

    Set joins = []
    Set rs3 = ##class(%SQL.Statement).%New()
    Do rs3.%Prepare("SELECT target, policy, minSucceeded FROM sentai_model.""Join"" WHERE flow = ?")
    Set result3 = rs3.%Execute(flow.%Id())
    While result3.%Next() {
        Do joins.%Push({"target": (result3.%Get("target")), "policy": (result3.%Get("policy")), "minSucceeded": (result3.%Get("minSucceeded"))})
    }
    Do out.%Set("joins", joins)

    Set out.canvasGeometry = ""
    Try {
        If (flow.canvasGeometry.Size > 0) {
            Set out.canvasGeometry = ##class(%DynamicAbstractObject).%FromJSON(flow.canvasGeometry.Read(flow.canvasGeometry.Size))
        }
    } Catch { }

    Quit out
}

/// --- /flows/{id}/validate (FR-012–FR-015, User Story 2) ---
ClassMethod ValidateFlow(flowId As %String) As %Status
{
    Quit ..WriteJSON(200, ##class(sentai.validation.FlowValidator).Validate(flowId, ..CurrentToken()))
}

/// --- /flows/{id}/dispatch (FR-016–FR-018, User Story 3) ---
ClassMethod DispatchFlow(flowId As %String) As %Status
{
    Set payload = ..ReadJSONBody()
    Set confirmations = $S($IsObject(payload) && payload.%IsDefined("confirmations"):payload."confirmations", 1:[])

    // Spec 005 ID-1: a run acts as one operator. An optional run credential (E-1) is redeemed
    // before any run exists, and must belong to the requesting user (research.md R-8).
    Set accessToken = ..CurrentToken(), refreshToken = ""
    Set carried = $S($IsObject(payload) && $IsObject(payload.runCredential):payload.runCredential.refreshToken, 1:"")
    If (carried '= "") {
        Set httpStatus = 0, location = ""
        Set pair = ##class(sentai.dispatch.AdminApiClient).Post("/api/admin/refresh", ..CurrentToken(), {"refresh_token": (carried)}, .httpStatus, .location)
        If (httpStatus '= 200) || '$IsObject(pair) || (pair."access_token" = "") {
            Quit ..WriteProblem(401, "Unauthorized", ..PlatformText(pair, httpStatus))
        }
        If ($ZCVT(pair.sub, "U") '= $ZCVT(..CurrentUser(), "U")) {
            Quit ..WriteProblem(403, "Forbidden", "RUN_CREDENTIAL_USER_MISMATCH: the run credential belongs to '"_pair.sub_"', not to the dispatching user '"_..CurrentUser()_"'")
        }
        // Redeeming revoked the access token paired with that refresh token, which the canvas
        // also sends as this request's bearer: the rest of the request uses the fresh one.
        Set accessToken = pair."access_token", refreshToken = pair."refresh_token"
    }

    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(flowId, confirmations, ..CurrentUser(), .errorCode, .errorDetail, .report, accessToken)

    If (errorCode = "VALIDATION_FAILED") Quit ..WriteJSON(422, report)
    If (errorCode = "CONFIRMATION_REQUIRED") Quit ..WriteProblem(428, "Confirmation Required", "Step '"_errorDetail_"' requires a matching typed confirmation before dispatch")
    If (errorCode = "INTERNAL_ERROR") Quit ..WriteProblem(500, "Internal Error", errorDetail)

    // E-1: with a run credential the run holds its fresh pair and renews it; otherwise it uses
    // the request's own token.
    Do ##class(sentai.dispatch.WaveDispatcher).StoreRunCredential(run.guid, accessToken, refreshToken)
    Do ##class(sentai.dispatch.WaveDispatcher).StartBackgroundLoop(run.guid, accessToken)

    Quit ..WriteJSON(202, ..ShapeRun(run, 0))
}

/// --- /runs (FR-024, User Story 3/4) ---
ClassMethod ListRuns() As %Status
{
    Set flowId = %request.Get("flowId")
    Set out = []
    Set rs = ##class(%SQL.Statement).%New()
    If (flowId '= "") {
        Do rs.%Prepare("SELECT %ID AS rowId FROM sentai_model.Run WHERE flow = ? ORDER BY startedAt DESC")
        Set result = rs.%Execute(flowId)
    } Else {
        Do rs.%Prepare("SELECT %ID AS rowId FROM sentai_model.Run ORDER BY startedAt DESC")
        Set result = rs.%Execute()
    }
    While result.%Next() {
        Set run = ##class(sentai.model.Run).%OpenId(result.%Get("rowId"), 0)
        Do out.%Push(..ShapeRun(run, 0))
    }
    Quit ..WriteJSON(200, out)
}

ClassMethod ReadRun(runGuid As %String) As %Status
{
    Set run = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0, .sc)
    If '$IsObject(run) Quit ..WriteProblem(404, "Not Found", "Run '"_runGuid_"' does not exist")
    Quit ..WriteJSON(200, ..ShapeRun(run, 1))
}

ClassMethod ShapeRun(run As sentai.model.Run, detail As %Boolean) As %DynamicObject
{
    Set out = {}
    Do out.%Set("guid", run.guid)
    Do out.%Set("flowId", run.flowGetObjectId())
    Do out.%Set("flowRevision", run.flowRevision)
    Do out.%Set("state", run.state)
    Do out.%Set("startedAt", run.startedAt)
    Do out.%Set("finishedAt", run.finishedAt)
    Do out.%Set("dispatchedBy", run.dispatchedBy)
    Quit:'detail out

    Do out.%Set("totalDurationMs", run.TotalDurationMs())

    Set steps = [], sumMs = 0
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT %ID AS rowId FROM sentai_model.StepRun WHERE run = ?")
    Set result = rs.%Execute(run.%Id())
    While result.%Next() {
        Set sr = ##class(sentai.model.StepRun).%OpenId(result.%Get("rowId"), 0)
        Do steps.%Push(..ShapeStepRun(sr))
        If (sr.timeStarted '= "") {
            Set endTs = $S(sr.timeFinished '= "":sr.timeFinished, 1:$ZDATETIME($HOROLOG, 3))
            Set sumMs = sumMs + ##class(sentai.model.Run).MillisecondsBetween(sr.timeStarted, endTs)
        }
    }
    Do out.%Set("steps", steps)
    Do out.%Set("sumOfStepsMs", sumMs)

    Set log = []
    Set rs2 = ##class(%SQL.Statement).%New()
    Do rs2.%Prepare("SELECT at, stepId, severity, message FROM sentai_model.LogEntry WHERE run = ? ORDER BY at DESC")
    Set result2 = rs2.%Execute(run.%Id())
    While result2.%Next() {
        Do log.%Push({"at": (result2.%Get("at")), "stepId": (result2.%Get("stepId")), "severity": (result2.%Get("severity")), "message": (result2.%Get("message"))})
    }
    Do out.%Set("log", log)

    Quit out
}

ClassMethod ShapeStepRun(sr As sentai.model.StepRun) As %DynamicObject
{
    Set out = {}
    Do out.%Set("guid", sr.guid)
    Do out.%Set("stepId", sr.stepId)
    Do out.%Set("state", sr.state)
    Do out.%Set("timeQueued", sr.timeQueued)
    Do out.%Set("timeStarted", sr.timeStarted)
    Do out.%Set("timeFinished", sr.timeFinished)
    Do out.%Set("failureReason", sr.failureReason)
    Do out.%Set("progressCurrent", sr.progressCurrent)
    Do out.%Set("progressTotal", sr.progressTotal)
    Do out.%Set("confirmedBy", sr.confirmedBy)
    Do out.%Set("confirmedAt", sr.confirmedAt)
    // Spec 005: who ran an in-process step, and the report it produced ({} when none).
    Do out.%Set("executedAs", sr.executedAs)
    Set result = {}
    If (sr.result '= "") {
        Try {
            Set result = ##class(%DynamicAbstractObject).%FromJSON(sr.result)
        }
        Catch {
            Set result = {}
        }
    }
    Do out.%Set("result", result)
    Quit out
}

/// --- /runs/{guid}/events (FR-025, FR-026, User Story 4, contracts/sse-protocol.md) ---
ClassMethod StreamEvents(runGuid As %String) As %Status
{
    Set run = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0, .sc)
    If '$IsObject(run) Quit ..WriteProblem(404, "Not Found", "Run '"_runGuid_"' does not exist")
    Set %response.ContentType = "text/event-stream"
    Do %response.SetHeader("Cache-Control", "no-cache")
    // %CSP.REST turns output flushing off; without this every Flush() below is ignored and the
    // gateway delivers the whole stream only when the request ends (observed, TD-03).
    Set %response.AllowOutputFlush = 1
    Do %response.Flush()

    // -1 so the first pass always emits the current state, even for a run still at version 0.
    Set lastVersion = -1
    Set maxDurationSeconds = $G(^sentaiRun("%config", "sseMaxDurationSeconds"), 600)
    Set startedAt = $ZH

    // A client that goes away surfaces as a write error on the next event; that ends the stream.
    Try {
        For {
            // Other processes (the dispatch loop, its workers) change the run; re-read it.
            Do run.%Reload()

            If (run.eventVersion > lastVersion) {
                Do ..EmitRunStateEvents(run, .lastVersion)
            }

            Quit:($LISTFIND($LB("completed", "failed", "cancelled"), run.state))
            Quit:(($ZH - startedAt) > maxDurationSeconds)

            Hang 0.5
        }
    }
    Catch {
        Return $$$OK
    }

    If $LISTFIND($LB("completed", "failed", "cancelled"), run.state) {
        Set event = {}
        Do event.%Set("runGuid", run.guid)
        Do event.%Set("eventVersion", run.eventVersion)
        Do event.%Set("type", "run-terminal")
        Do event.%Set("at", $ZDATETIME($HOROLOG, 3))
        Do event.%Set("state", run.state)
        Write "event: run-terminal", $C(10)
        Write "data: "_event.%ToJSON(), $C(10), $C(10)
        Do %response.Flush()
    }

    Quit $$$OK
}

/// Emits step-state-changed events for every StepRun whose state changed since
/// `lastVersion` — a conservative approximation (re-emits current state of any StepRun
/// touched since) that never diverges from what GET /runs/{guid} would show.
ClassMethod EmitRunStateEvents(run As sentai.model.Run, ByRef lastVersion As %Integer) As %Status
{
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT guid, stepId, state, progressCurrent, progressTotal FROM sentai_model.StepRun WHERE run = ?")
    Set result = rs.%Execute(run.%Id())
    While result.%Next() {
        Set event = {}
        Do event.%Set("runGuid", run.guid)
        Do event.%Set("eventVersion", run.eventVersion)
        Do event.%Set("type", "step-state-changed")
        Do event.%Set("at", $ZDATETIME($HOROLOG, 3))
        Set step = {}
        Do step.%Set("stepId", result.%Get("stepId"))
        Do step.%Set("guid", result.%Get("guid"))
        Do step.%Set("state", result.%Get("state"))
        Do step.%Set("progressCurrent", result.%Get("progressCurrent"))
        Do step.%Set("progressTotal", result.%Get("progressTotal"))
        Do event.%Set("step", step)

        Write "event: step-state-changed", $C(10)
        Write "data: "_event.%ToJSON(), $C(10), $C(10)
    }
    Do %response.Flush()
    Set lastVersion = run.eventVersion
    Quit $$$OK
}

/// --- Run/step control (FR-027–FR-030, User Story 4) ---
ClassMethod CancelRun(runGuid As %String) As %Status
{
    Do ##class(sentai.dispatch.WaveDispatcher).CancelRun(runGuid)
    Quit ..WriteJSON(202, {})
}

ClassMethod PauseRun(runGuid As %String) As %Status
{
    Do ##class(sentai.dispatch.WaveDispatcher).PauseRun(runGuid)
    Quit ..WriteJSON(202, {})
}

ClassMethod CancelStep(runGuid As %String, stepGuid As %String) As %Status
{
    Set sc = ##class(sentai.dispatch.WaveDispatcher).CancelStep(runGuid, stepGuid)
    If $$$ISERR(sc) Quit ..WriteProblem(404, "Not Found", $SYSTEM.Status.GetErrorText(sc))
    Quit ..WriteJSON(202, {})
}

ClassMethod PauseStep(runGuid As %String, stepGuid As %String) As %Status
{
    Set sc = ##class(sentai.dispatch.WaveDispatcher).PauseStep(runGuid, stepGuid)
    If $$$ISERR(sc) {
        Set text = $SYSTEM.Status.GetErrorText(sc)
        If (text [ "SentaiNotPausable") Quit ..WriteProblem(409, "Conflict", text)
        Quit ..WriteProblem(404, "Not Found", text)
    }
    Quit ..WriteJSON(202, {})
}

ClassMethod RerunStep(runGuid As %String, stepGuid As %String) As %Status
{
    // Spec 005 ID-2: a re-run executes under the dispatcher's identity and credential, so only
    // the dispatcher may ask for one.
    Set run = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0)
    If $IsObject(run) && ($ZCVT(..CurrentUser(), "U") '= $ZCVT(run.dispatchedBy, "U")) {
        Quit ..WriteProblem(403, "Forbidden", "RERUN_NOT_BY_DISPATCHER: only '"_run.dispatchedBy_"', who dispatched this run, may re-run its steps")
    }
    Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(runGuid, stepGuid, .newGuid)
    If $$$ISERR(sc) Quit ..WriteProblem(409, "Conflict", $SYSTEM.Status.GetErrorText(sc))

    Set stepRun = ##class(sentai.model.StepRun).GuidIndexOpen(newGuid, 0)
    Quit ..WriteJSON(202, ..ShapeStepRun(stepRun))
}

/// --- Step-type catalog (FR-037, User Story 6) ---
ClassMethod ListStepTypes() As %Status
{
    Quit ..WriteJSON(200, ##class(sentai.registry.StepType).GetCatalog())
}

/// --- /catalog/tasks (spec 006: every value is the platform's own, read with the caller's token) ---
ClassMethod ListCatalogTasks() As %Status
{
    Set q = %request.Get("q")
    Set namespace = %request.Get("namespace")
    Set filter = $S(%request.Get("filter") '= "":%request.Get("filter"), 1:"all")
    Set destructiveOnly = $S(%request.Get("destructiveOnly") '= "":%request.Get("destructiveOnly"), 1:"0")
    Quit ..WriteOutcome(##class(sentai.catalog.TaskService).List(..CurrentToken(), q, namespace, filter, destructiveOnly))
}

ClassMethod ReadCatalogTask(taskId As %String) As %Status
{
    Quit ..WriteOutcome(##class(sentai.catalog.TaskService).Read(taskId, ..CurrentToken()))
}

ClassMethod SuspendCatalogTask(taskId As %String) As %Status
{
    Set payload = ..ReadJSONBody()
    Set suspended = 1
    If $IsObject(payload) && payload.%IsDefined("suspended") {
        If (payload.%GetTypeOf("suspended") '= "boolean") Quit ..WriteProblem(400, "Bad Request", "suspended must be a boolean")
        Set suspended = payload.suspended
    }
    Quit ..WriteOutcome(##class(sentai.catalog.TaskService).SetSuspended(taskId, suspended, ..CurrentToken()))
}

/// --- /wqm/categories (FR-033–FR-036, User Story 5) ---
ClassMethod ListWqmCategories() As %Status
{
    Quit ..WriteJSON(200, ##class(sentai.wqm.CategoryService).List(..CurrentToken()))
}

ClassMethod ReadWqmCategory(name As %String) As %Status
{
    Set cat = ##class(sentai.wqm.CategoryService).Read(name, "", ..CurrentToken())
    If '$IsObject(cat) Quit ..WriteProblem(404, "Not Found", "Category '"_name_"' does not exist")
    Quit ..WriteJSON(200, cat)
}

ClassMethod WriteWqmCategory(name As %String) As %Status
{
    Set payload = ..ReadJSONBody()
    Do payload.%Set("name", name)
    Set sc = ##class(sentai.wqm.CategoryService).Write(payload, ..CurrentToken())
    If $$$ISERR(sc) Quit ..WriteProblem(422, "Validation Failed", $SYSTEM.Status.GetErrorText(sc))
    Quit ..WriteJSON(200, {})
}

/// --- /flows/{id}/schedule (FR-031, FR-032, User Story 5) ---
ClassMethod ScheduleFlow(flowId As %String) As %Status
{
    Set payload = ..ReadJSONBody()
    // Blocks before any %SYS.Task is created: validation errors (FR-032) and any destructive
    // step (out of scope for scheduling in v1, TD-06).
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(flowId, ..CurrentToken())
    If '##class(sentai.validation.FlowValidator).HasNoErrors(report) {
        Quit ..WriteJSON(422, report)
    }

    // Each task is created by the platform with the operator's token; its refusal is the answer.
    Set outcome = ##class(sentai.dispatch.NativeScheduler).Schedule(flowId, ..CurrentToken())
    If (outcome.httpStatus '= 200) Quit ..WriteOutcome(outcome)
    Set taskIds = outcome.body.taskIds

    Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 4)
    Set flow.scheduleSpec = payload.scheduleSpec
    Do flow.%Save()

    Set out = {}
    Do out.%Set("taskIds", taskIds)
    Do out.%Set("nextRun", ..NextRunFor(payload.scheduleSpec))
    Quit ..WriteJSON(201, out)
}

/// Root steps (no incoming edge) start a run when their native task fires — they call back into
/// POST /flows/{id}/dispatch on OnTask(); tasks for downstream steps exist only to satisfy "one
/// task id per scheduled step" (research.md R-007/OQ-1). Tasks are created by
/// sentai.dispatch.NativeScheduler through the platform's management API.
ClassMethod StepHasIncomingEdge(flowId As %String, stepId As %String) As %Boolean
{
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai_model.Edge WHERE flow = ? AND target = ?")
    Set result = rs.%Execute(flowId, stepId)
    Do result.%Next()
    Quit (result.%Get("c") > 0)
}

ClassMethod NextRunFor(scheduleSpec As %String) As %String
{
    Quit $ZDATETIME($HOROLOG, 3)
}

/// --- Body parsing ---
ClassMethod ReadJSONBody() As %DynamicObject
{
    Set body = ""
    Try {
        Set body = {}.%FromJSON(%request.Content)
    }
    Catch {
        Set body = {}
    }
    Quit body
}

}
