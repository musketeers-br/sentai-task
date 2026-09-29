/// Spec 018 US4 (plan D-5, research R-8): an overview area as an ordinary one-step flow, like
/// spec 010's example flow. Application layer only: the REST handler checks the definition's
/// structure and shapes the answer, as `POST /flows` does (Constitution I). The new flow passes
/// the one validation gate, so it can be scheduled with the existing endpoint (FR-015).
Class sentai.overview.AreaFlow Extends %RegisteredObject
{

/// `{httpStatus: 200, body: definition}`, or 404 unknown area, 409 area without a step type,
/// 422 parameter findings — nothing is created in any case.
ClassMethod Definition(area As %String, parameters, token As %String) As %DynamicObject
{
    If '$IsObject(##class(sentai.overview.Areas).Lookup(area)) {
        Quit ##class(sentai.catalog.TaskService).Problem(404, "UNKNOWN_AREA: '"_area_"' is not an overview area")
    }
    Set type = ##class(sentai.overview.Areas).StepTypeOf(area)
    If (type = "") {
        Set out = ##class(sentai.catalog.TaskService).Problem(409, "AREA_HAS_NO_STEP_TYPE: the '"_area_"' area cannot become a flow")
        Set out.problem.title = "Conflict"
        Quit out
    }
    Set findings = ##class(sentai.overview.OverviewService).ParameterFindings(type, parameters)
    If $IsObject(findings) Quit {"httpStatus": 422, "body": (findings)}

    Set label = ##class(sentai.registry.StepType).Lookup(type).label
    Set category = ..Category(token)
    Set def = {
        "name": (..FreeName("Check: "_label)), "defaultCategory": (category),
        "steps": [{"id": "01", "type": (type), "taskName": (label), "namespace": "%SYS", "wqmCategory": (category),
                   "parameters": ($S($IsObject(parameters):parameters, 1:{}))}],
        "edges": [], "joins": [],
        "canvasGeometry": {"nodes": {"01": {"x": 40, "y": 160}}}
    }
    Quit ##class(sentai.catalog.TaskService).Ok(def)
}

/// Stores `def` and validates it through the one gate: `{flowId, validation}`, or the save error.
ClassMethod Save(def As %DynamicObject, user As %String, token As %String, Output flowId As %String) As %Status
{
    Set flowId = ""
    Quit ##class(sentai.model.Flow).SaveGraph(def, "", 0, user, .flowId)
}

ClassMethod Validation(flowId As %String, token As %String) As %DynamicObject
{
    Quit ##class(sentai.validation.FlowValidator).Validate(flowId, token)
}

/// `Default` when the platform lists it, else the first category it lists, else `Default`
/// (validation then reports what it reports).
ClassMethod Category(token As %String) As %String
{
    Set list = ##class(sentai.wqm.CategoryService).List(token), first = ""
    Set it = list.%GetIterator()
    While it.%GetNext(.k, .c) {
        Continue:'$IsObject(c)
        Return:(c.name = "Default") "Default"
        Set:(first = "") first = c.name
    }
    Quit $S(first '= "":first, 1:"Default")
}

/// `base`, or `base (2)`, `base (3)`… — flow names are unique, case-insensitively.
ClassMethod FreeName(base As %String) As %String
{
    Quit:'##class(sentai.model.Flow).NameIndexExists(base) base
    For n = 2:1 { Set name = base_" ("_n_")"  Quit:'##class(sentai.model.Flow).NameIndexExists(name) }
    Quit name
}

}
