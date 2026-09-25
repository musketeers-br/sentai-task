/// The only class that decides "what runs now" and the only class (besides CategoryService)
/// that talks to %SYS.WorkQueueMgr and to the administrative API's asynchronous endpoints
/// (FR-020, research.md R-005). Owns the dispatch transaction, wave eligibility, StepRun
/// transitions, and run/step control (pause/cancel/rerun).
Class sentai.dispatch.WaveDispatcher Extends %RegisteredObject
{

/// Assumed 1:1 mapping from step type to its asynchronous administrative endpoint
/// (research.md risk #4 / OQ-02) — only `integrity-check` has real validated evidence
/// (001-validate-async-job-contract, evidence/06-integrity-check-start.json); the other
/// endpoints follow the same observed URL pattern (`/api/admin/v2/<resource>/<action>`)
/// and MUST be individually confirmed against a real instance before this plan is
/// considered technically done (plan.md TD-02).
ClassMethod AdminEndpointFor(type As %String) As %String
{
    Return $CASE(type,
        "integrity-check":      "/api/admin/v2/database-dir/integrity-check",
        "compact-globals":      "/api/admin/v2/database-dir/compact-globals",
        "defragment-globals":   "/api/admin/v2/database-dir/defragment",
        "switch-journal":       "/api/admin/v2/journal/switch",
        "purge-audit-records":  "/api/admin/v2/audit/purge",
        "purge-task-history":   "/api/admin/v2/task-history/purge",
        "custom":               "/api/admin/v2/task/custom",
        : "")
}

/// Writes the ^sentaiRun resolution registry entries inside the caller's transaction
/// (FR-043, data-model.md):
///   ^sentaiRun(runGuid)            = $lb(flowId, flowRevision, startedAt, dispatchedBy)
///   ^sentaiRun(runGuid, stepId)    = stepRunGuid
///   ^sentaiRun("idx", stepRunGuid) = $lb(runGuid, stepId)
ClassMethod IndexRun(runGuid As %String, flowId As %String, flowRevision As %Integer, startedAt As %String, dispatchedBy As %String) As %Status
{
    Set ^sentaiRun(runGuid) = $LB(flowId, flowRevision, startedAt, dispatchedBy)
    Return $$$OK
}

ClassMethod IndexStepRun(runGuid As %String, stepId As %String, stepRunGuid As %String) As %Status
{
    Set ^sentaiRun(runGuid, stepId) = stepRunGuid
    Set ^sentaiRun("idx", stepRunGuid) = $LB(runGuid, stepId)
    Return $$$OK
}

/// Resolves an execution identifier observed in the platform's own operational records
/// (messages.log) back to the run/step it belongs to, in a single lookup (FR-043).
ClassMethod ResolveRunStep(stepRunGuid As %String, ByRef runGuid As %String, ByRef stepId As %String) As %Boolean
{
    Set entry = $G(^sentaiRun("idx", stepRunGuid))
    If (entry = "") Quit 0
    Set runGuid = $LG(entry, 1)
    Set stepId = $LG(entry, 2)
    Return 1
}

/// Dispatches `flowId`: blocks on structural validation errors (FR-018), blocks on
/// missing/mismatched destructive confirmations (FR-017), then creates Run + one StepRun
/// per step + the ^sentaiRun index, all inside one transaction (FR-016, NFR-002, NFR-004,
/// research.md R-011). Returns the Run as a %DynamicObject on success.
/// 
/// On failure returns "" and sets `errorCode`/`errorDetail`:
///   "VALIDATION_FAILED"       — see `validationReport` for the ValidationReport
///   "CONFIRMATION_REQUIRED"   — errorDetail names the pending stepId (FR-017, HTTP 428)
/// `bearerToken` is passed to validation (category existence, spec 004 FR-006); the scheduled
/// path has none.
ClassMethod Dispatch(flowId As %String, confirmationsArray As %DynamicArray, dispatchedBy As %String, ByRef errorCode As %String, ByRef errorDetail As %String, ByRef validationReport As %DynamicObject, bearerToken As %String = "") As %DynamicObject
{
    Set errorCode = "", errorDetail = ""

    // FR-018: structural validation blocks dispatch regardless of any earlier /validate call.
    Set validationReport = ##class(sentai.validation.FlowValidator).Validate(flowId, bearerToken)
    If '##class(sentai.validation.FlowValidator).HasNoErrors(validationReport) {
        Set errorCode = "VALIDATION_FAILED"
        Return ""
    }

    // FR-017: every destructive step needs a matching typed confirmation before ANY step starts.
    If '..CheckConfirmations(flowId, confirmationsArray, .pendingStepId) {
        Set errorCode = "CONFIRMATION_REQUIRED"
        Set errorDetail = pendingStepId
        Return ""
    }

    Quit ..CreateRun(flowId, confirmationsArray, dispatchedBy, .errorCode, .errorDetail)
}

/// FR-017 gate on its own: true when every destructive step of `flowId` has a typed
/// confirmation matching its database directory (or namespace when it has none). On the first
/// missing or mismatched confirmation returns 0 and sets `pendingStepId`.
ClassMethod CheckConfirmations(flowId As %String, confirmationsArray As %DynamicArray, ByRef pendingStepId As %String) As %Boolean
{
    Set pendingStepId = ""
    Kill confirmed
    If (confirmationsArray '= "") {
        Set iter = confirmationsArray.%GetIterator()
        While iter.%GetNext(.k, .c) {
            Set confirmed(c.stepId) = c.typedName
        }
    }

    Set stepRs = ##class(%SQL.Statement).%New()
    Do stepRs.%Prepare("SELECT id, type, namespace, databaseDirectory FROM sentai_model.Step WHERE flow = ?")
    Set stepResult = stepRs.%Execute(flowId)
    While stepResult.%Next() {
        Set stepId = stepResult.%Get("id")
        Set type = stepResult.%Get("type")
        If ##class(sentai.registry.StepType).IsDestructive(type) {
            Set expected = $S(stepResult.%Get("databaseDirectory") '= "":stepResult.%Get("databaseDirectory"), 1:stepResult.%Get("namespace"))
            If '$D(confirmed(stepId)) || (confirmed(stepId) '= expected) {
                Set pendingStepId = stepId
                Quit
            }
        }
    }
    Quit (pendingStepId = "")
}

/// Creates Run + one StepRun per step + the ^sentaiRun index inside one transaction (FR-016,
/// NFR-002, NFR-004, research.md R-011), recording confirmedBy/At for the confirmed steps.
/// Applies no gate: Dispatch() calls it only after validation and confirmations passed.
/// On failure returns "" with errorCode "INTERNAL_ERROR".
ClassMethod CreateRun(flowId As %String, confirmationsArray As %DynamicArray, dispatchedBy As %String, ByRef errorCode As %String, ByRef errorDetail As %String) As %DynamicObject
{
    Set errorCode = "", errorDetail = "", result = ""
    Kill confirmed
    If (confirmationsArray '= "") {
        Set iter = confirmationsArray.%GetIterator()
        While iter.%GetNext(.k, .c) {
            Set confirmed(c.stepId) = c.typedName
        }
    }

    Set sc = $$$OK
    TSTART
    Try {
        Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 0, .sc)
        $$$ThrowOnError(sc)

        Set run = ##class(sentai.model.Run).%New()
        Set run.guid = $SYSTEM.Util.CreateGUID()
        Do run.flowSetObjectId(flowId)
        Set run.flowRevision = flow.revision
        Set run.dispatchedBy = dispatchedBy
        Set run.state = "running"
        Set run.startedAt = $ZDATETIME($HOROLOG, 3)
        Set sc = run.%Save()
        $$$ThrowOnError(sc)

        Do ..IndexRun(run.guid, flowId, flow.revision, run.startedAt, dispatchedBy)

        Set stepRs2 = ##class(%SQL.Statement).%New()
        Do stepRs2.%Prepare("SELECT id FROM sentai_model.Step WHERE flow = ?")
        Set stepResult2 = stepRs2.%Execute(flowId)
        While stepResult2.%Next() {
            Set stepId = stepResult2.%Get("id")
            Set stepRun = ##class(sentai.model.StepRun).%New()
            Set stepRun.guid = $SYSTEM.Util.CreateGUID()
            Do stepRun.runSetObjectId(run.%Id())
            Set stepRun.stepId = stepId
            Set stepRun.state = "queued"
            Set stepRun.timeQueued = $ZDATETIME($HOROLOG, 3)
            If $D(confirmed(stepId)) {
                Set stepRun.confirmedBy = dispatchedBy
                Set stepRun.confirmedAt = $ZDATETIME($HOROLOG, 3)
            }
            Set sc = stepRun.%Save()
            $$$ThrowOnError(sc)

            Do ..IndexStepRun(run.guid, stepId, stepRun.guid)
        }

        TCOMMIT
        Set result = run
    }
    Catch ex {
        TROLLBACK 1
        Set errorCode = "INTERNAL_ERROR"
        Set errorDetail = ex.DisplayString()
        Return ""
    }
    Quit result
}

/// Starts the background execution loop for `runGuid` as an IRIS job, right after the
/// dispatch transaction commits (research.md R-005). `bearerToken` is forwarded so the
/// background job can call the administrative API on the operator's behalf.
ClassMethod StartBackgroundLoop(runGuid As %String, bearerToken As %String) As %Status
{
    JOB ..RunLoop(runGuid, bearerToken)
    Return $$$OK
}

/// The background dispatch loop: computes eligible steps, enqueues them, polls their
/// asynchronous jobs, applies transitions (including join-failure propagation), and
/// recomputes eligibility after every terminal transition — until the run itself reaches
/// a terminal state.
ClassMethod RunLoop(runGuid As %String, bearerToken As %String) As %Status
{
    Set run = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0, .sc)
    If '$IsObject(run) Quit sc

    For {
        Kill eligible
        Set n = ..ComputeEligibleSteps(runGuid, .anyFailed, .eligible)

        Set i = ""
        For {
            Set i = $O(eligible(i))
            Quit:i=""
            Do ..StartStep(run, eligible(i))
        }

        // Poll every in-flight (queued-with-job / running) step for completion.
        Do ..PollInFlightSteps(run, bearerToken)

        If ..IsRunTerminal(run.%Id()) Quit
        Hang 0.5
    }

    Do ..FinalizeRun(run)
    Return $$$OK
}

/// A step becomes eligible once every source of its incoming edges is terminal and
/// satisfies the join's ALL_MUST_SUCCEED policy (FR-019). When any required input fails,
/// the target transitions directly to `failed` — never enqueued (FR-021).
ClassMethod ComputeEligibleSteps(runGuid As %String, ByRef anyFailed As %Boolean, ByRef eligible) As %Integer
{
    Kill eligible
    Set anyFailed = 0
    Set run = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0, .sc)
    If '$IsObject(run) Return 0
    Set flowId = run.flowGetObjectId()

    Set stepRs = ##class(%SQL.Statement).%New()
    Do stepRs.%Prepare("SELECT id FROM sentai_model.Step WHERE flow = ?")
    Set stepResult = stepRs.%Execute(flowId)
    Set n = 0
    While stepResult.%Next() {
        Set stepId = stepResult.%Get("id")
        Set stepRun = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), stepId, 4)
        Continue:'$IsObject(stepRun)
        Continue:(stepRun.state '= "queued")
        Continue:(stepRun.adminJobId '= "")

        // Gather source states over incoming edges.
        Set edgeRs = ##class(%SQL.Statement).%New()
        Do edgeRs.%Prepare("SELECT source FROM sentai_model.Edge WHERE flow = ? AND target = ?")
        Set edgeResult = edgeRs.%Execute(flowId, stepId)
        Set allSourcesTerminal = 1, anySourceFailed = 0, sourceCount = 0
        While edgeResult.%Next() {
            Set sourceCount = sourceCount + 1
            Set srcRun = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), edgeResult.%Get("source"), 0)
            If '$IsObject(srcRun) { Set allSourcesTerminal = 0 Continue }
            If '$LISTFIND($LB("completed", "failed", "cancelled"), srcRun.state) Set allSourcesTerminal = 0
            If $LISTFIND($LB("failed", "cancelled"), srcRun.state) Set anySourceFailed = 1
        }

        If (sourceCount > 0) && 'allSourcesTerminal Continue

        If (sourceCount > 0) && anySourceFailed {
            // ALL_MUST_SUCCEED: any required input failing fails the target directly (FR-021).
            Do stepRun.TransitionTo("failed", "One or more required inputs failed")
            Set anyFailed = 1
            Continue
        }

        Set n = n + 1
        Set eligible(n) = stepId
    }
    Return n
}

/// Enqueues one eligible step as a unit of work in %SYS.WorkQueueMgr under its WQM
/// category, then calls the asynchronous administrative endpoint mapped to its type. The
/// StepRun transitions to `running` once the administrative API accepts the job (202).
ClassMethod StartStep(run As sentai.model.Run, stepId As %String) As %Status
{
    Set flowId = run.flowGetObjectId()
    Set stepRun = ##class(sentai.model.StepRun).OpenForRunStep(run.%Id(), stepId, 0, .sc)
    If '$IsObject(stepRun) Return sc
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(flowId, stepId, 0, .sc)
    If '$IsObject(step) Return sc

    Set category = $S(step.wqmCategory '= "":step.wqmCategory, 1:run.flow.defaultCategory)
    // The Work Queue Manager API is %SYSTEM.WorkMgr; the category must already exist on the
    // platform. A refusal fails this step with the platform's own message (FR-023) instead of
    // killing the background loop.
    Set queueMgr = $SYSTEM.WorkMgr.%New(, , category)
    If '$IsObject(queueMgr) {
        Return stepRun.TransitionTo("failed", $SYSTEM.Status.GetErrorText($GET(%objlasterror)))
    }

    // Actual execution: the async administrative endpoint (R-005) — parallelism/ceilings
    // are entirely the Work Queue Manager's, this call only starts the underlying job.
    Set sc = queueMgr.Queue("##class(sentai.dispatch.WaveDispatcher).ExecuteStepAsync", stepRun.guid)
    If $$$ISOK(sc) Set sc = queueMgr.Sync()
    If $$$ISERR(sc) {
        Do stepRun.%Reload()
        If (stepRun.state = "queued") Return stepRun.TransitionTo("failed", $SYSTEM.Status.GetErrorText(sc))
    }

    Return $$$OK
}

/// Runs on a %SYS.WorkQueueMgr worker: calls the mapped administrative endpoint to start
/// the underlying job, records the returned async-result id, and transitions the StepRun
/// to `running`. Polling for completion happens in PollInFlightSteps (owning process).
ClassMethod ExecuteStepAsync(stepRunGuid As %String) As %Status
{
    Set stepRun = ##class(sentai.model.StepRun).GuidIndexOpen(stepRunGuid, 4, .sc)
    If '$IsObject(stepRun) Quit $S($$$ISERR(sc):sc, 1:$$$ERROR($$$GeneralError, "SentaiNotFound: step run "_stepRunGuid))

    Set run = stepRun.run
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(run.flowGetObjectId(), stepRun.stepId, 0, .sc3)
    Quit:'$IsObject(step) $$$OK

    Set endpoint = ..AdminEndpointFor(step.type)
    Set httpStatus = 0, location = ""
    // The platform rejects an empty POST (400 "HTTP POST has no content"); the validated start
    // request carries an empty JSON object (spec 001 evidence/06-integrity-check-start.json).
    Do ##class(sentai.dispatch.AdminApiClient).Post(endpoint, $G(^sentaiRun(run.guid, "%token")), {}, .httpStatus, .location)

    If (httpStatus = 202) && (location '= "") {
        Set stepRun.adminJobId = location
        Do stepRun.%Save()
        Do stepRun.TransitionTo("running")
    } Else {
        Do stepRun.TransitionTo("failed", "Administrative endpoint "_endpoint_" returned HTTP "_httpStatus)
    }
    Return $$$OK
}

/// Polls every `running` StepRun of the run whose adminJobId is set, applying the
/// terminal transition and copying failureReason verbatim from the platform (FR-023).
ClassMethod PollInFlightSteps(run As sentai.model.Run, bearerToken As %String) As %Status
{
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT %ID AS rowId FROM sentai_model.StepRun WHERE run = ? AND state = 'running'")
    Set result = rs.%Execute(run.%Id())
    While result.%Next() {
        Set stepRun = ##class(sentai.model.StepRun).%OpenId(result.%Get("rowId"), 4)
        Continue:(stepRun.adminJobId = "")

        Set httpStatus = 0, location = ""
        Set body = ##class(sentai.dispatch.AdminApiClient).Get(stepRun.adminJobId, bearerToken, .httpStatus, .location)
        // A 4xx is permanent for this run (e.g. 401 once the 60 s credential expired, E-1):
        // fail the step with the status recorded instead of polling a job we can no longer
        // read, which left the step — and the run — "running" forever. 5xx/network: retry.
        If (httpStatus >= 400) && (httpStatus < 500) {
            Set summary = $S($IsObject(body) && $IsObject(body."status"):body."status"."summary", 1:"")
            Do stepRun.TransitionTo("failed", "Administrative endpoint "_stepRun.adminJobId_" returned HTTP "_httpStatus_$S(summary '= "":": "_summary, 1:""))
            Continue
        }
        Continue:'$IsObject(body)

        Set state = $S($IsObject(body."result"):body."result"."State", 1:"")
        If (state = "Finished") {
            Do stepRun.TransitionTo("completed")
        } ElseIf (state = "Error") || (state = "Failed") {
            Set reason = $S($IsObject(body."status") && (body."status"."summary" '= ""):body."status"."summary", 1:"Administrative job reported "_state)
            Do stepRun.TransitionTo("failed", reason)
        }
    }
    Return $$$OK
}

ClassMethod IsRunTerminal(runId As %String) As %Boolean
{
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT COUNT(*) AS c FROM sentai_model.StepRun WHERE run = ? AND state NOT IN ('completed','failed','cancelled')")
    Set result = rs.%Execute(runId)
    Do result.%Next()
    Return (result.%Get("c") = 0)
}

ClassMethod FinalizeRun(run As sentai.model.Run) As %Status
{
    // Constitution IV: a partial outcome is never reported as success — failed outranks
    // cancelled, which outranks completed.
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT SUM(CASE WHEN state = 'failed' THEN 1 ELSE 0 END) AS failed, SUM(CASE WHEN state = 'cancelled' THEN 1 ELSE 0 END) AS cancelled FROM sentai_model.StepRun WHERE run = ?")
    Set result = rs.%Execute(run.%Id())
    Do result.%Next()
    // The loop's copy was loaded at start; pick up every eventVersion bump since, so the save
    // below never writes a stale value back.
    Do run.%Reload()
    Set run.state = $S(+result.%Get("failed") > 0:"failed", +result.%Get("cancelled") > 0:"cancelled", 1:"completed")
    Set run.finishedAt = $ZDATETIME($HOROLOG, 3)
    Set sc = run.%Save()
    If $$$ISERR(sc) Return sc
    Return ##class(sentai.model.Run).BumpEventVersionFor(run.%Id())
}

/// --- Control operations (FR-027, FR-028, FR-029, FR-030) ---
/// Whole-run pause: suspends dispatch of not-yet-started steps. Steps already running
/// are left to finish (v1 does not support pausing a running step outside the purge
/// family from the run-level action — individual PauseStep does, for pausable types).
ClassMethod PauseRun(runGuid As %String) As %Status
{
    Set ^sentaiRun(runGuid, "%paused") = 1
    Quit $$$OK
}

/// Whole-run cancel: stops dispatch of not-yet-started steps and requests cancellation
/// of whatever is already running (FR-027).
ClassMethod CancelRun(runGuid As %String) As %Status
{
    Set ^sentaiRun(runGuid, "%paused") = 1
    Set run = ##class(sentai.model.Run).GuidIndexOpen(runGuid, 0, .sc)
    If '$IsObject(run) Quit $$$ERROR($$$GeneralError, "SentaiNotFound")
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT %ID AS rowId FROM sentai_model.StepRun WHERE run = ? AND state IN ('queued','running','paused')")
    Set result = rs.%Execute(run.%Id())
    While result.%Next() {
        Set stepRun = ##class(sentai.model.StepRun).%OpenId(result.%Get("rowId"), 4)
        Do stepRun.TransitionTo("cancelled")
    }
    Quit $$$OK
}

/// Individual-step cancel — affects only that step, no impact on the rest of the wave
/// (FR-028).
ClassMethod CancelStep(runGuid As %String, stepGuid As %String) As %Status
{
    Set stepRun = ##class(sentai.model.StepRun).GuidIndexOpen(stepGuid, 4, .sc)
    If '$IsObject(stepRun) Quit $$$ERROR($$$GeneralError, "SentaiNotFound")
    Quit stepRun.TransitionTo("cancelled")
}

/// Individual-step pause — refused (409) for any type outside the purge family (FR-029).
/// Returns $$$ERROR("SentaiNotPausable") when the type does not support pause in v1.
ClassMethod PauseStep(runGuid As %String, stepGuid As %String) As %Status
{
    Set stepRun = ##class(sentai.model.StepRun).GuidIndexOpen(stepGuid, 4, .sc)
    If '$IsObject(stepRun) Quit $$$ERROR($$$GeneralError, "SentaiNotFound")

    Set run = stepRun.run
    Set step = ##class(sentai.model.Step).FlowStepIndexOpen(run.flowGetObjectId(), stepRun.stepId, 0, .sc3)
    If '$IsObject(step) Quit $$$ERROR($$$GeneralError, "SentaiNotFound")

    If '##class(sentai.registry.StepType).IsPausable(step.type) {
        Quit $$$ERROR($$$GeneralError, "SentaiNotPausable: step type '"_step.type_"' does not support pause in v1")
    }

    If (stepRun.adminJobId '= "") {
        Set httpStatus = 0, location = ""
        // spec 001 evidence/08a-async-result-pause.json: POST /api/admin/v2/async-result/pause?id=<id>
        Set jobId = $PIECE(stepRun.adminJobId, "id=", 2)
        Do ##class(sentai.dispatch.AdminApiClient).Post("/api/admin/v2/async-result/pause?id="_jobId, $G(^sentaiRun(runGuid, "%token")), {}, .httpStatus, .location)
    }
    Quit stepRun.TransitionTo("paused")
}

/// Re-runs a `failed` step within the same run: creates a new StepRun identifier, starting
/// from `queued`, with no effect on any other step (FR-030).
ClassMethod RerunStep(runGuid As %String, stepGuid As %String, ByRef newStepRunGuid As %String) As %Status
{
    Set oldStepRun = ##class(sentai.model.StepRun).GuidIndexOpen(stepGuid, 0, .sc)
    If '$IsObject(oldStepRun) Quit $$$ERROR($$$GeneralError, "SentaiNotFound")
    If (oldStepRun.state '= "failed") Quit $$$ERROR($$$GeneralError, "SentaiNotFailed: only a failed step can be re-run")

    // Spec 004 FR-002: rerun bypasses validation, so it checks v1 availability itself — a failed
    // step of a type the target platform does not support is never sent to it again.
    Set flowId = oldStepRun.run.flowGetObjectId(), stepId = oldStepRun.stepId, type = ""
    &sql(SELECT type INTO :type FROM sentai_model.Step WHERE flow = :flowId AND id = :stepId)
    If '##class(sentai.registry.StepType).IsAvailable(type) {
        Quit $$$ERROR($$$GeneralError, "STEP_TYPE_NOT_SUPPORTED_ON_TARGET: step '"_stepId_"' type '"_type_"' is not supported on the target platform in v1")
    }

    Set newStepRun = ##class(sentai.model.StepRun).%New()
    Set newStepRun.guid = $SYSTEM.Util.CreateGUID()
    Do newStepRun.runSetObjectId(oldStepRun.runGetObjectId())
    Set newStepRun.stepId = oldStepRun.stepId
    Set newStepRun.state = "queued"
    Set newStepRun.timeQueued = $ZDATETIME($HOROLOG, 3)
    Set sc = newStepRun.%Save()
    If $$$ISERR(sc) Quit sc

    Do ..IndexStepRun(runGuid, oldStepRun.stepId, newStepRun.guid)
    Set newStepRunGuid = newStepRun.guid
    Quit $$$OK
}

}
