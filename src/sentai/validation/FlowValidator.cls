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
/// `bearerToken` is the operator's platform credential. With it, the WQM category-existence rule
/// (spec 004 FR-006) reads the platform's category list once; without it (scheduled fire time,
/// spec 004 D-2) that rule is skipped.
ClassMethod Validate(flowId As %String, bearerToken As %String = "") As %DynamicObject
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

    // Category names known to the platform, read with the operator's credential. An unreadable
    // list is empty, so every step reports CATEGORY_NOT_FOUND (fail closed).
    Set checkCategories = (bearerToken '= "")
    If checkCategories {
        Kill knownCategory
        Set catIter = ##class(sentai.wqm.CategoryService).List(bearerToken).%GetIterator()
        While catIter.%GetNext(.k, .cat) {
            Set:(cat.name '= "") knownCategory(cat.name) = ""
        }
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

        // 3. Closed catalog, v1 availability (spec 004 FR-002) and per-step-type parameter schema.
        If '##class(sentai.registry.StepType).IsKnownType(type) {
            Do errors.%Push({"stepId": (stepId), "code": "UNKNOWN_STEP_TYPE", "message": ("Step type '"_type_"' is not in the closed catalog")})
        } Else {
            If '##class(sentai.registry.StepType).IsAvailable(type) {
                Do errors.%Push({"stepId": (stepId), "code": "STEP_TYPE_NOT_SUPPORTED_ON_TARGET", "message": ("Step type '"_type_"' is not supported on the target platform in v1 (supported: "_##class(sentai.registry.StepType).AvailableTypes()_")")})
            }
            If (type = "purge-audit-records") {
                Set hasDaysToKeep = $IsObject(step.parameters) && step.parameters.%IsDefined("daysToKeep")
                If 'hasDaysToKeep {
                    Do errors.%Push({"stepId": (stepId), "code": "PARAMETER_SCHEMA", "parameter": "daysToKeep", "message": "purge-audit-records requires parameters.daysToKeep"})
                }
            }
            // Spec 005: in-process types — the step's parameters against the declared schema, and
            // the catalog's class installed. (purge-audit-records declares its schema for the
            // canvas only and keeps the rule above.)
            If (##class(sentai.registry.StepType).GetExecutor(type) = "in-process") {
                Do ..DeclaredStepFindings(stepId, type, ##class(sentai.registry.StepType).GetParameterSchema(type), step.parameters, ##class(sentai.registry.StepType).GetTargetClass(type), errors)
            }
        }

        // 4. Namespace existence on the active instance.
        Set ns = step.namespace
        If (ns '= "") && '##class(%SYS.Namespace).Exists(ns) {
            Do errors.%Push({"stepId": (stepId), "code": "NAMESPACE_NOT_FOUND", "message": ("Namespace '"_ns_"' does not exist on this instance")})
        }

        // 5. The step's effective WQM category exists on the platform (spec 004 FR-006) — the
        //    same resolution the dispatcher uses at enqueue.
        If checkCategories {
            Set effective = $S(step.wqmCategory '= "":step.wqmCategory, 1:flow.defaultCategory)
            If (effective = "") || '$D(knownCategory(effective)) {
                Do errors.%Push({"stepId": (stepId), "code": "CATEGORY_NOT_FOUND", "message": ("WQM category '"_effective_"' does not exist on the target platform")})
            }
        }

        // 6. WQM category nesting invariant (shared with CategoryService).
        Set category = step.wqmCategory
        If (category '= "") {
            Set cat = ##class(sentai.model.Category).NameIndexOpen(category, 0, .catSc)
            If $IsObject(cat) && '##class(sentai.model.Category).SatisfiesInvariant(cat.defaultWorkers, cat.maxActiveWorkers, cat.maxWorkers, cat.maxTotalWorkers) {
                Do errors.%Push({"stepId": (stepId), "code": "WQM_INVARIANT_VIOLATED", "message": ("WQM category '"_category_"' violates defaultWorkers<=maxActiveWorkers<=maxWorkers<=maxTotalWorkers")})
            }
        }

        // 7. Fixed database-directory mount precondition — warning only, never an error (FR-014).
        Set dbDir = step.databaseDirectory
        If (dbDir '= "") && ..IsMountedReadOnly(dbDir) {
            Do warnings.%Push({"stepId": (stepId), "code": "PRECONDITION_READ_ONLY", "message": "Database mounted read-only. This step type requires write access to the directory."})
        }
    }

    Return ..Report(errors, warnings)
}

/// Spec 005 FR-005 / R-6: findings for one in-process step. `schema` and `className` are the
/// catalog's (passed in so the rule is testable against any schema); the step's own keys are
/// only compared with the schema, never used to select code. Each PARAM_* finding names its
/// `parameter` (spec 007 BD-1).
ClassMethod DeclaredStepFindings(stepId As %String, type As %String, schema As %DynamicArray, parameters As %DynamicObject, className As %String, errors As %DynamicArray)
{
    Set prefix = "Step '"_stepId_"' ("_type_"): "
    Set hasParameters = $IsObject(parameters)
    Kill declared
    Set iter = schema.%GetIterator()
    While iter.%GetNext(.k, .def) {
        Set declared(def.name) = ""
    }

    If hasParameters {
        Set iter = parameters.%GetIterator()
        While iter.%GetNext(.key, .value) {
            Continue:$D(declared(key))
            Do errors.%Push({"stepId": (stepId), "code": "PARAM_UNKNOWN", "parameter": (key), "message": (prefix_"unknown parameter '"_key_"'")})
        }
    }

    Set iter = schema.%GetIterator()
    While iter.%GetNext(.k, .def) {
        Set name = def.name
        If 'hasParameters || 'parameters.%IsDefined(name) {
            If def.required {
                Do errors.%Push({"stepId": (stepId), "code": "PARAM_REQUIRED", "parameter": (name), "message": (prefix_"parameter '"_name_"' is required")})
            }
            Continue
        }
        Set value = parameters.%Get(name), jsonType = parameters.%GetTypeOf(name)
        Set ok = $CASE(def.type,
            "integer": (jsonType = "number") && ($NUMBER(value, "I") '= ""),
            "number": (jsonType = "number"),
            "boolean": (jsonType = "boolean"),
            "string": (jsonType = "string"),
            : 0)
        If 'ok {
            Set expected = $CASE(def.type, "integer": "an integer", "number": "a number", "boolean": "a boolean", "string": "a string", : "of type "_def.type)
            Do errors.%Push({"stepId": (stepId), "code": "PARAM_TYPE_MISMATCH", "parameter": (name), "message": (prefix_"parameter '"_name_"' must be "_expected)})
            Continue
        }
        Continue:'$LISTFIND($LB("integer", "number"), def.type)
        Set hasMin = def.%IsDefined("min"), hasMax = def.%IsDefined("max")
        If (hasMin && (value < def.min)) || (hasMax && (value > def.max)) {
            Set bounds = $S(hasMin && hasMax:"between "_def.min_" and "_def.max, hasMin:"at least "_def.min, 1:"at most "_def.max)
            Do errors.%Push({"stepId": (stepId), "code": "PARAM_OUT_OF_RANGE", "parameter": (name), "message": (prefix_"parameter '"_name_"' must be "_bounds)})
        }
    }

    If '##class(sentai.registry.StepType).ClassIsInstalled(className) {
        Do errors.%Push({"stepId": (stepId), "code": "STEP_TYPE_NOT_SUPPORTED_ON_TARGET", "message": ("Step type '"_type_"' is not supported on the target platform: its declared class is not installed")})
    }
}

/// The report /schedule blocks on (FR-032): everything Validate() reports, plus one error per
/// destructive step — scheduling a flow with any destructive step is out of scope in v1, since
/// no approved mechanism supplies SC-006's typed confirmation at fire time (spec.md Change Log
/// 2026-09-22). Scoped to scheduling only: /validate and /dispatch keep calling Validate(), so
/// destructive steps stay valid for manual dispatch with typed confirmation (FR-017).
ClassMethod ValidateForSchedule(flowId As %String, bearerToken As %String = "") As %DynamicObject
{
    Set report = ..Validate(flowId, bearerToken)

    Set stepRs = ##class(%SQL.Statement).%New()
    Do stepRs.%Prepare("SELECT id, type FROM sentai_model.Step WHERE flow = ?")
    Set stepResult = stepRs.%Execute(flowId)
    While stepResult.%Next() {
        Set stepId = stepResult.%Get("id"), type = stepResult.%Get("type")
        If ##class(sentai.registry.StepType).IsDestructive(type) {
            Do report."errors".%Push({"stepId": (stepId), "code": "DESTRUCTIVE_NOT_SCHEDULABLE", "message": ("Step type '"_type_"' is destructive; flows with destructive steps are not schedulable in v1 and must be dispatched manually with typed confirmation")})
        }
        // Spec 005 ID-3: an in-process step runs as the dispatching operator; a scheduled run has
        // none (it would run as the Task Manager's run-as user), so it is not schedulable.
        If (##class(sentai.registry.StepType).GetExecutor(type) = "in-process") {
            Do report."errors".%Push({"stepId": (stepId), "code": "IN_PROCESS_NOT_SCHEDULABLE", "message": ("Step '"_stepId_"' ("_type_") runs inside the platform as the dispatching operator and cannot run in a scheduled run")})
        }
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
