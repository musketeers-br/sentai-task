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
    Do stepRs.%Prepare("SELECT id, type, customClass, databaseDirectory, namespace, wqmCategory, parameters FROM sentai_model.Step WHERE flow = ?")
    Set stepResult = stepRs.%Execute(flowId)
    While stepResult.%Next() {
        Set stepId = stepResult.%Get("id")
        Set type = stepResult.%Get("type")

        // 2. custom-with-no-class is always an error, never a warning (FR-011).
        If (type = "custom") && (stepResult.%Get("customClass") = "") {
            Do errors.%Push({"stepId": (stepId), "code": "CUSTOM_CLASS_REQUIRED", "message": "A custom step requires a declared customClass before it can validate"})
        }

        // 3. Per-step-type parameter schema (closed catalog).
        If '##class(sentai.registry.StepType).IsKnownType(type) {
            Do errors.%Push({"stepId": (stepId), "code": "UNKNOWN_STEP_TYPE", "message": ("Step type '"_type_"' is not in the closed catalog")})
        } ElseIf (type = "purge-audit-records") {
            Set paramsText = stepResult.%Get("parameters")
            Set hasDaysToKeep = 0
            Try {
                If (paramsText '= "") {
                    Set p = ##class(%DynamicAbstractObject).%FromJSON(paramsText)
                    Set hasDaysToKeep = p.%IsDefined("daysToKeep")
                }
            } Catch { Set hasDaysToKeep = 0 }
            If 'hasDaysToKeep {
                Do errors.%Push({"stepId": (stepId), "code": "PARAMETER_SCHEMA", "message": "purge-audit-records requires parameters.daysToKeep"})
            }
        }

        // 4. Namespace existence on the active instance.
        Set ns = stepResult.%Get("namespace")
        If (ns '= "") && '##class(%SYS.Namespace).Exists(ns) {
            Do errors.%Push({"stepId": (stepId), "code": "NAMESPACE_NOT_FOUND", "message": ("Namespace '"_ns_"' does not exist on this instance")})
        }

        // 5. WQM category nesting invariant (shared with CategoryService).
        Set category = stepResult.%Get("wqmCategory")
        If (category '= "") {
            Set catId = ##class(sentai.model.Category).NameIndexOpen(category, 0, .catSc)
            If (catId '= "") {
                Set cat = ##class(sentai.model.Category).%OpenId(catId, 0, .catSc)
                If $IsObject(cat) && '##class(sentai.model.Category).SatisfiesInvariant(cat.defaultWorkers, cat.maxActiveWorkers, cat.maxWorkers, cat.maxTotalWorkers) {
                    Do errors.%Push({"stepId": (stepId), "code": "WQM_INVARIANT_VIOLATED", "message": ("WQM category '"_category_"' violates defaultWorkers<=maxActiveWorkers<=maxWorkers<=maxTotalWorkers")})
                }
            }
        }

        // 6. Fixed database-directory mount precondition — warning only, never an error (FR-014).
        Set dbDir = stepResult.%Get("databaseDirectory")
        If (dbDir '= "") && ..IsMountedReadOnly(dbDir) {
            Do warnings.%Push({"stepId": (stepId), "code": "PRECONDITION_READ_ONLY", "message": "Database mounted read-only. This step type requires write access to the directory."})
        }
    }

    Return ..Report(errors, warnings)
}

/// The single fixed precondition check (not a general engine, FR-014): is the database
/// directory's underlying mount currently read-only? Reads the live filesystem/IRIS
/// directory-manager state — never persisted, always evaluated fresh (FR-015).
ClassMethod IsMountedReadOnly(databaseDirectory As %String) As %Boolean
{
    Set testFile = databaseDirectory _ "/.sentai-write-probe"
    Set result = 0
    Try {
        Set stream = ##class(%Stream.FileCharacter).%New()
        Set stream.Filename = testFile
        Set sc = stream.Write("probe")
        If $$$ISERR(sc) {
            Set result = 1
        } Else {
            Do stream.%Delete(testFile)
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
