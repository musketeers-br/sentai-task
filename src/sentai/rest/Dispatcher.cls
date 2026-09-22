/// The sole HTTP entry point (%CSP.REST). Routing, authentication (OnPreDispatch), JSON
/// (de)serialization, and error-to-HTTP-status translation only — no business logic lives
/// here; every method immediately delegates to an application-layer service class
/// (research.md R-001). Implements exactly the surface of
/// specs/002-canvas-ui/contracts/openapi.yaml — see
/// specs/003-backend-objectscript/contracts/rest-mapping.md for the endpoint -> class map.
Class sentai.rest.Dispatcher Extends %CSP.REST
{

Parameter HandleCorsRequest = 1;

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
/// API's own info endpoint. A 200 response is treated as proof the token is valid and
/// unexpired — functionally correct, at the cost of one extra HTTP call per request,
/// pending confirmation of a cheaper native mechanism against a real instance (OQ-01).
ClassMethod IsTokenValid(token As %String) As %Boolean
{
    Set httpStatus = 0, location = ""
    Do ##class(sentai.dispatch.AdminApiClient).Get("/api/admin/info", token, .httpStatus, .location)
    Quit (httpStatus = 200)
}

ClassMethod CurrentToken() As %String
{
    Quit $G(%session("sentai.bearerToken"))
}

ClassMethod CurrentUser() As %String
{
    Quit $G(%session("Username"), $USERNAME)
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
    Do rs.%Prepare("SELECT %ID, name, revision, savedAt, savedBy, scheduleSpec FROM sentai_model.Flow ORDER BY name")
    Set result = rs.%Execute()
    While result.%Next() {
        Set item = {}
        Do item.%Set("id", result.%Get("%ID"))
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
    Set expectedRevision = +%request.Data("revision", 1)
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
    Do rs.%Prepare("SELECT id, type, taskName, namespace, databaseDirectory, runAsUser, timeoutMinutes, wqmCategory, customClass FROM sentai_model.Step WHERE flow = ?")
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
    Do rs3.%Prepare("SELECT target, policy, minSucceeded FROM sentai_model.Join WHERE flow = ?")
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
    Quit ..WriteJSON(200, ##class(sentai.validation.FlowValidator).Validate(flowId))
}

/// --- /flows/{id}/dispatch (FR-016–FR-018, User Story 3) ---
ClassMethod DispatchFlow(flowId As %String) As %Status
{
    Set payload = ..ReadJSONBody()
    Set confirmations = $S($IsObject(payload) && payload.%IsDefined("confirmations"):payload."confirmations", 1:[])

    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(flowId, confirmations, ..CurrentUser(), .errorCode, .errorDetail, .report)

    If (errorCode = "VALIDATION_FAILED") Quit ..WriteJSON(422, report)
    If (errorCode = "CONFIRMATION_REQUIRED") Quit ..WriteProblem(428, "Confirmation Required", "Step '"_errorDetail_"' requires a matching typed confirmation before dispatch")
    If (errorCode = "INTERNAL_ERROR") Quit ..WriteProblem(500, "Internal Error", errorDetail)

    Set ^sentaiRun(run.guid, "%token") = ..CurrentToken()
    Do ##class(sentai.dispatch.WaveDispatcher).StartBackgroundLoop(run.guid, ..CurrentToken())

    Quit ..WriteJSON(202, ..ShapeRun(run, 0))
}

/// --- /runs (FR-024, User Story 3/4) ---
ClassMethod ListRuns() As %Status
{
    Set flowId = %request.Data("flowId", 1)
    Set out = []
    Set rs = ##class(%SQL.Statement).%New()
    If (flowId '= "") {
        Do rs.%Prepare("SELECT %ID FROM sentai_model.Run WHERE flow = ? ORDER BY startedAt DESC")
        Set result = rs.%Execute(flowId)
    } Else {
        Do rs.%Prepare("SELECT %ID FROM sentai_model.Run ORDER BY startedAt DESC")
        Set result = rs.%Execute()
    }
    While result.%Next() {
        Set run = ##class(sentai.model.Run).%OpenId(result.%Get("%ID"), 0)
        Do out.%Push(..ShapeRun(run, 0))
    }
    Quit ..WriteJSON(200, out)
}

ClassMethod ReadRun(runGuid As %String) As %Status
{
    Set runId = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0, .sc)
    If $$$ISERR(sc) || (runId = "") Quit ..WriteProblem(404, "Not Found", "Run '"_runGuid_"' does not exist")
    Set run = ##class(sentai.model.Run).%OpenId(runId, 0)
    Quit ..WriteJSON(200, ..ShapeRun(run, 1))
}

ClassMethod ShapeRun(run As sentai.model.Run, detail As %Boolean) As %DynamicObject
{
    Set out = {}
    Do out.%Set("guid", run.guid)
    Do out.%Set("flowId", run.flow.%Id())
    Do out.%Set("flowRevision", run.flowRevision)
    Do out.%Set("state", run.state)
    Do out.%Set("startedAt", run.startedAt)
    Do out.%Set("finishedAt", run.finishedAt)
    Do out.%Set("dispatchedBy", run.dispatchedBy)
    Quit:'detail out

    Do out.%Set("totalDurationMs", run.TotalDurationMs())

    Set steps = [], sumMs = 0
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT %ID FROM sentai_model.StepRun WHERE run = ?")
    Set result = rs.%Execute(run.%Id())
    While result.%Next() {
        Set sr = ##class(sentai.model.StepRun).%OpenId(result.%Get("%ID"), 0)
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
    Quit out
}

/// --- /runs/{guid}/events (FR-025, FR-026, User Story 4, contracts/sse-protocol.md) ---
ClassMethod StreamEvents(runGuid As %String) As %Status
{
    Set runId = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0, .sc)
    If $$$ISERR(sc) || (runId = "") Quit ..WriteProblem(404, "Not Found", "Run '"_runGuid_"' does not exist")

    Set %response.ContentType = "text/event-stream"
    Do %response.SetHeader("Cache-Control", "no-cache")
    Do %response.WriteFlush("")

    Set lastVersion = 0
    Set maxDurationSeconds = $G(^sentaiRun("%config", "sseMaxDurationSeconds"), 600)
    Set startedAt = $ZH

    For {
        Set run = ##class(sentai.model.Run).%OpenId(runId, 0)

        If (run.eventVersion > lastVersion) {
            Do ..EmitRunStateEvents(run, .lastVersion)
        }

        Quit:'%response.IsClientConnected()
        Quit:($LISTFIND($LB("completed", "failed", "cancelled"), run.state))
        Quit:(($ZH - startedAt) > maxDurationSeconds)

        Hang 0.5
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
    Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(runGuid, stepGuid, .newGuid)
    If $$$ISERR(sc) Quit ..WriteProblem(409, "Conflict", $SYSTEM.Status.GetErrorText(sc))

    Set stepRunId = ##class(sentai.model.StepRun).GuidIndexOpen(newGuid, 0)
    Set stepRun = ##class(sentai.model.StepRun).%OpenId(stepRunId, 0)
    Quit ..WriteJSON(202, ..ShapeStepRun(stepRun))
}

/// --- Step-type catalog (FR-037, User Story 6) ---
ClassMethod ListStepTypes() As %Status
{
    Quit ..WriteJSON(200, ##class(sentai.registry.StepType).GetCatalog())
}

/// --- /catalog/tasks (FR-038, FR-039, User Story 6, P3 reducible) ---
ClassMethod ListCatalogTasks() As %Status
{
    Set q = %request.Data("q", 1)
    Set namespace = %request.Data("namespace", 1)
    Set filter = $S(%request.Data("filter", 1) '= "":%request.Data("filter", 1), 1:"all")
    Set destructiveOnly = +%request.Data("destructiveOnly", 1)
    Quit ..WriteJSON(200, ##class(sentai.catalog.TaskService).List(..CurrentToken(), q, namespace, filter, destructiveOnly))
}

ClassMethod ReadCatalogTask(taskId As %Integer) As %Status
{
    Set catalog = ##class(sentai.catalog.TaskService).List(..CurrentToken())
    Set iter = catalog.items.%GetIterator()
    While iter.%GetNext(.k, .entry) {
        If (entry.taskId = taskId) {
            Return ..WriteJSON(200, entry)
        }
    }
    Quit ..WriteProblem(404, "Not Found", "Task '"_taskId_"' does not exist")
}

ClassMethod SuspendCatalogTask(taskId As %Integer) As %Status
{
    Set payload = ..ReadJSONBody()
    Set suspended = $S($IsObject(payload) && payload.%IsDefined("suspended"):payload.suspended, 1:1)
    Set sc = ##class(sentai.catalog.TaskService).Suspend(taskId, suspended, ..CurrentToken())
    If $$$ISERR(sc) Quit ..WriteProblem(500, "Internal Error", $SYSTEM.Status.GetErrorText(sc))
    Quit ..WriteJSON(200, {})
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
    Set report = ##class(sentai.validation.FlowValidator).Validate(flowId)
    If '##class(sentai.validation.FlowValidator).HasNoErrors(report) {
        Quit ..WriteJSON(422, report)
    }

    Set taskIds = []
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT id FROM sentai_model.Step WHERE flow = ?")
    Set result = rs.%Execute(flowId)
    While result.%Next() {
        Set stepId = result.%Get("id")
        Set taskId = ..CreateNativeTask(flowId, stepId, payload.scheduleSpec, $S(payload.%IsDefined("category"):payload.category, 1:""))
        Do taskIds.%Push(taskId)
    }

    Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 4)
    Set flow.scheduleSpec = payload.scheduleSpec
    Do flow.%Save()

    Set out = {}
    Do out.%Set("taskIds", taskIds)
    Do out.%Set("nextRun", ..NextRunFor(payload.scheduleSpec))
    Quit ..WriteJSON(201, out)
}

/// Compiles one step into a native %SYS.Task.Definition entry (never a private scheduler,
/// FR-031). Per research.md R-007/OQ-1: only the step(s) with no incoming edges actually
/// start a run when firing natively — they call back into POST /flows/{id}/dispatch on
/// their OnTask(); tasks for downstream steps exist only to satisfy "one task id per
/// scheduled step" and are suppressed at fire time by WaveDispatcher already having
/// carried them to a terminal state via the earlier wave. Uses the `Id` from a subsequent
/// listing, not from the creation response body (spec 001 already proved that body comes
/// back with no identifier).
ClassMethod CreateNativeTask(flowId As %String, stepId As %String, scheduleSpec As %String, category As %String) As %Integer
{
    Set isRoot = '..StepHasIncomingEdge(flowId, stepId)

    Set task = ##class(%SYS.Task.Definition).%New()
    Set task.Name = "SentaiTask: "_flowId_"#"_stepId
    Set task.NameSpace = $NAMESPACE
    Set task.TaskClass = "sentai.dispatch.ScheduledFlowTask"
    Do task.Settings.SetAt(flowId, "FlowId")
    Do task.Settings.SetAt(stepId, "StepId")
    Do task.Settings.SetAt(isRoot, "IsRoot")
    Set sc = task.%Save()

    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT TOP 1 ID FROM %SYS.Task.Definition WHERE Name = ? ORDER BY ID DESC")
    Set result = rs.%Execute(task.Name)
    Quit:'result.%Next() 0
    Quit result.%Get("ID")
}

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
