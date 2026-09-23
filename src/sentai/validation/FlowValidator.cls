/// The only class that produces a ValidationReport. Reused, unchanged, by /validate,
/// /schedule, and /dispatch (FR-012, FR-018, FR-032) — never a duplicated copy of a rule.
/// Runs rules in a fixed order: structural/schema, acyclicity, per-step-type parameter
/// schema, namespace existence, WQM category invariant, database-directory mount
/// precondition (warning only).
Class sentai.validation.FlowValidator Extends %RegisteredObject
{

/// Validates the currently PERSISTED flow (as saved) and returns the ValidationReport
/// shape from openapi.yaml: {"errors": [...], "warnings": [...]}, each entry shaped as
/// {"stepId", "code", "message"} (the Finding schema).
ClassMethod Validate(flowId As %String) As %DynamicObject
{
    Set errors = []
    Set warnings = []

    Set flow = ##class(sentai.model.Flow).%OpenId(flowId, 0, .sc)
    If $$$ISERR(sc) {
        Do errors.%Push({"stepId": "", "code": "FLOW_NOT_FOUND", "message": "Flow does not exist"})
        Quit ..Report(errors, warnings)
    }

    // 1. Acyclicity (reuses the same algorithm as the mutation-time check).
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT source, target FROM sentai_model.Edge WHERE flow = ?")
    Set result = rs.%Execute(flowId)
    Set edgesArray = []
    While result.%Next() {
        Do edgesArray.%Push({"source": (result.%Get("source")), "target": (result.%Get("target"))})
    }
    If ##class(sentai.model.Edge).WouldGraphBeCyclic(flowId, edgesArray) {
        Do errors.%Push({"stepId": "", "code": "CYCLE_DETECTED", "message": "The flow's edge graph contains a cycle"})
    }

    // Iterate steps for per-type rules.
    Set stepRs = ##class(%SQL.Statement).%New()
    Do stepRs.%Prepare("SELECT %ID AS rowId FROM sentai_model.Step WHERE flow = ?")
    Set stepResult = stepRs.%Execute(flowId)
    While stepResult.%Next() {
        Set step = ##class(sentai.model.Step).%OpenId(stepResult.%Get("rowId"), 0)
        Continue:'$IsObject(step)
        Set stepId = step.id
        Set type = step.type

        // 2. custom-with-no-class is always an error, never a warning (FR-011).
        If (type = "custom") && (step.customClass = "") {
            Do errors.%Push({"stepId": (stepId), "code": "CUSTOM_CLASS_REQUIRED", "message": "A custom step requires a declared customClass before it can validate"})
        }

        // 3. Per-step-type parameter schema (closed catalog).
        If '##class(sentai.registry.StepType).IsKnownType(type) {
            Do errors.%Push({"stepId": (stepId), "code": "UNKNOWN_STEP_TYPE", "message": ("Step type '"_type_"' is not in the closed catalog")})
        } ElseIf (type = "purge-audit-records") {
            Set hasDaysToKeep = $IsObject(step.parameters) && step.parameters.%IsDefined("daysToKeep")
            If 'hasDaysToKeep {
                Do errors.%Push({"stepId": (stepId), "code": "PARAMETER_SCHEMA", "message": "purge-audit-records requires parameters.daysToKeep"})
            }
        }

        // 4. Namespace existence on the active instance.
        Set ns = step.namespace
        If (ns '= "") && '##class(%SYS.Namespace).Exists(ns) {
            Do errors.%Push({"stepId": (stepId), "code": "NAMESPACE_NOT_FOUND", "message": ("Namespace '"_ns_"' does not exist on this instance")})
        }

        // 5. WQM category nesting invariant (shared with CategoryService).
        Set category = step.wqmCategory
        If (category '= "") {
            Set cat = ##class(sentai.model.Category).NameIndexOpen(category, 0, .catSc)
            If $IsObject(cat) && '##class(sentai.model.Category).SatisfiesInvariant(cat.defaultWorkers, cat.maxActiveWorkers, cat.maxWorkers, cat.maxTotalWorkers) {
                Do errors.%Push({"stepId": (stepId), "code": "WQM_INVARIANT_VIOLATED", "message": ("WQM category '"_category_"' violates defaultWorkers<=maxActiveWorkers<=maxWorkers<=maxTotalWorkers")})
            }
        }

        // 6. Fixed database-directory mount precondition — warning only, never an error (FR-014).
        Set dbDir = step.databaseDirectory
        If (dbDir '= "") && ..IsMountedReadOnly(dbDir) {
            Do warnings.%Push({"stepId": (stepId), "code": "PRECONDITION_READ_ONLY", "message": "Database mounted read-only. This step type requires write access to the directory."})
        }
    }

    Return ..Report(errors, warnings)
}

/// The report /schedule blocks on (FR-032): everything Validate() reports, plus one error per
/// destructive step — scheduling a flow with any destructive step is out of scope in v1, since
/// no approved mechanism supplies SC-006's typed confirmation at fire time (spec.md Change Log
/// 2026-09-22). Scoped to scheduling only: /validate and /dispatch keep calling Validate(), so
/// destructive steps stay valid for manual dispatch with typed confirmation (FR-017).
ClassMethod ValidateForSchedule(flowId As %String) As %DynamicObject
{
    Set report = ..Validate(flowId)

    Set stepRs = ##class(%SQL.Statement).%New()
    Do stepRs.%Prepare("SELECT id, type FROM sentai_model.Step WHERE flow = ?")
    Set stepResult = stepRs.%Execute(flowId)
    While stepResult.%Next() {
        Continue:'##class(sentai.registry.StepType).IsDestructive(stepResult.%Get("type"))
        Do report."errors".%Push({"stepId": (stepResult.%Get("id")), "code": "DESTRUCTIVE_NOT_SCHEDULABLE", "message": ("Step type '"_stepResult.%Get("type")_"' is destructive; flows with destructive steps are not schedulable in v1 and must be dispatched manually with typed confirmation")})
    }
    Quit report
}

/// The single fixed precondition check (not a general engine, FR-014): is the database
/// directory's underlying mount currently read-only? Reads the live filesystem/IRIS
/// directory-manager state — never persisted, always evaluated fresh (FR-015).
ClassMethod IsMountedReadOnly(databaseDirectory As %String) As %Boolean
{
    // %Stream.FileCharacter.Write() only buffers — nothing touches the filesystem until
    // %Save(), so the probe opens the file directly with a zero timeout instead.
    Set testFile = ##class(%File).NormalizeFilename(".sentai-write-probe", databaseDirectory)
    Set result = 1
    Try {
        Open testFile:("WNS"):0
        If $TEST {
            Close testFile
            Do ##class(%File).Delete(testFile)
            Set result = 0
        }
    }
    Catch {
        Set result = 1
    }
    Quit result
}

ClassMethod Report(errors As %DynamicArray, warnings As %DynamicArray) As %DynamicObject
{
    Set report = {}
    Do report.%Set("errors", errors)
    Do report.%Set("warnings", warnings)
    Quit report
}

/// True if `report` (as returned by Validate()) has zero errors — the blocking predicate
/// used by /dispatch and /schedule (FR-018, FR-032). Warnings never block.
ClassMethod HasNoErrors(report As %DynamicObject) As %Boolean
{
    Quit (report."errors".%Size() = 0)
}

}
