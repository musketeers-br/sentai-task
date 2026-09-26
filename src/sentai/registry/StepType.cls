/// Closed, compiled catalog of the step types (FR-037); `available` marks the support set
/// (spec 004 FR-001). Spec 005: each entry says how it executes (`executor`: the management
/// API, or `in-process` on a WQM worker as the dispatching operator) and, when it takes any,
/// declares its `parameters` schema. The class an in-process step runs is read from here only.
/// Data, not code branches (Constitution II) — no value here comes from runtime
/// configuration or operator input. See specs/003-backend-objectscript/data-model.md
/// §Step-type registry.
Class sentai.registry.StepType Extends %RegisteredObject
{

XData Catalog [ MimeType = application/json ]
{
[
  { "type": "integrity-check",        "label": "Integrity check",        "class": "%SYS.Task.IntegrityCheck",          "category": "verification", "executor": "platform-api", "destructive": false, "pausable": false, "available": true  },
  { "type": "compact-globals",        "label": "Compact globals",        "class": "%SYS.Task.CompactGlobals",          "category": "storage",      "executor": "platform-api", "destructive": false, "pausable": false, "available": false },
  { "type": "defragment-globals",     "label": "Defragment globals",     "class": "%SYS.Task.Defragment",              "category": "storage",      "executor": "platform-api", "destructive": false, "pausable": false, "available": false },
  { "type": "switch-journal",         "label": "Switch journal",         "class": "%SYS.Task.SwitchJournal",           "category": "journal",      "executor": "in-process",   "destructive": false, "pausable": false, "available": true ,
    "parameters": [] },
  { "type": "purge-audit-records",    "label": "Purge audit records",    "class": "%SYS.Task.PurgeAudit",              "category": "purge",        "executor": "platform-api", "destructive": true,  "pausable": true,  "available": false,
    "parameters": [
      { "name": "daysToKeep", "property": "KeepDays", "type": "integer", "required": true, "min": 1,
        "description": "Days of audit records to keep" }
    ] },
  { "type": "purge-task-history",     "label": "Purge task history",     "class": "%SYS.Task.PurgeTaskHistory",        "category": "purge",        "executor": "in-process",   "destructive": true,  "pausable": false, "available": false,
    "parameters": [
      { "name": "keepDays", "property": "KeepDays", "type": "integer", "required": false, "default": 30, "min": 0,
        "description": "Days of task history to keep" }
    ] },
  { "type": "storage-headroom-check", "label": "Storage headroom check", "class": "sentai.steps.StorageHeadroomCheck", "category": "storage",      "executor": "in-process",   "destructive": false, "pausable": false, "available": true ,
    "parameters": [
      { "name": "minFreePercent", "property": "MinFreePercent", "type": "number", "required": false, "default": 10, "min": 0, "max": 100,
        "description": "Fail when any database or journal location has less free space than this percentage" }
    ] },
  { "type": "db-size-report",         "label": "Database size report",   "class": "sentai.steps.DatabaseSizeReport",   "category": "verification", "executor": "in-process",   "destructive": false, "pausable": false, "available": true ,
    "parameters": [] },
  { "type": "custom",                 "label": "Custom (legacy)",        "class": "",                                  "category": "custom",       "executor": "platform-api", "destructive": false, "pausable": false, "available": false }
]
}

/// Returns the full catalog as a %DynamicArray — the sole reader of the XData block.
/// Every other class MUST call this method rather than duplicating the literal catalog.
ClassMethod GetCatalog() As %DynamicArray
{
    Set stream = ##class(%Dictionary.CompiledXData).%OpenId(..%ClassName(1)_"||Catalog").Data
    Quit ##class(%DynamicAbstractObject).%FromJSON(stream)
}

/// Looks up one entry by step type. Returns "" if the type is not in the closed catalog.
ClassMethod Lookup(type As %String) As %DynamicObject
{
    Set catalog = ..GetCatalog()
    Set iter = catalog.%GetIterator()
    While iter.%GetNext(.key, .entry) {
        If (entry.type = type) Quit
        Set entry = ""
    }
    Quit entry
}

/// Derives isDestructive for a step type — the sole source of truth (FR-010).
/// A "custom" step is never treated as destructive by the registry itself; a real
/// customClass subclass of %SYS.Task.Definition declares its own destructiveness,
/// which is outside this closed catalog's authority (data-model.md §Step types).
ClassMethod IsDestructive(type As %String) As %Boolean
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit 0
    Quit entry.destructive
}

/// Destructiveness of a platform task by its class (spec 006 FR-004): the `destructive` of the
/// catalog entry whose `class` equals `taskClass` exactly (case-sensitive, like platform class
/// names). `known` is 0 when no entry names that class; the entry's `type` is never matched.
ClassMethod DestructiveByClass(taskClass As %String, Output known As %Boolean) As %Boolean
{
    Set known = 0, destructive = 0
    Quit:(taskClass = "") 0
    Set iter = ..GetCatalog().%GetIterator()
    While iter.%GetNext(.key, .entry) {
        If (entry.class '= "") && (entry.class = taskClass) {
            Set known = 1, destructive = ''entry.destructive
            Quit
        }
    }
    Quit destructive
}

/// Whether pause is supported for the type in v1 — true only for the purge family
/// (the fixed "Pause: purge family only" decision).
ClassMethod IsPausable(type As %String) As %Boolean
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit 0
    Quit entry.pausable
}

/// Whether the type is in the v1 support set — proven end to end on the target platform
/// (spec 004 D-1: integrity-check only). Unavailable types stay in the catalog so saved flows
/// load, but validation and rerun refuse them with STEP_TYPE_NOT_SUPPORTED_ON_TARGET.
ClassMethod IsAvailable(type As %String) As %Boolean
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit 0
    Quit entry.available
}

/// The available types, in catalog order, comma-separated (for refusal messages).
ClassMethod AvailableTypes() As %String
{
    Set list = "", iter = ..GetCatalog().%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Set:entry.available list = list_$S(list = "":"", 1:", ")_entry.type
    }
    Quit list
}

/// Category the type belongs to (verification/storage/journal/purge/custom).
ClassMethod GetCategory(type As %String) As %String
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit ""
    Quit entry.category
}

/// The %SYS.Task.* class the type maps to; "" for "custom" (which uses Step.customClass
/// instead — a declared-by-the-operator class, never invented by this registry).
ClassMethod GetTargetClass(type As %String) As %String
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit ""
    Quit entry.class
}

/// True if the given type is one of the closed catalog's values.
ClassMethod IsKnownType(type As %String) As %Boolean
{
    Quit (..Lookup(type) '= "")
}

/// How a step of `type` executes: "platform-api" (asynchronous management endpoint) or
/// "in-process" (the catalog's class on a WQM worker, spec 005). "" for an unknown type.
ClassMethod GetExecutor(type As %String) As %String
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit ""
    Quit entry.executor
}

/// The declared parameter schema of `type` (data-model.md §Parameter definition); an empty
/// array when the type declares none or is unknown.
ClassMethod GetParameterSchema(type As %String) As %DynamicArray
{
    Set entry = ..Lookup(type)
    If (entry = "") || '$IsObject(entry.parameters) Quit []
    Quit entry.parameters
}

/// True when the entry of `type` declares a `parameters` schema — even an empty one, under
/// which every key a step carries is unknown.
ClassMethod DeclaresParameters(type As %String) As %Boolean
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit 0
    Quit (entry.%GetTypeOf("parameters") = "array")
}

/// Whether the catalog's class for `type` is installed on this instance (research.md R-6).
/// Only the catalog's `class` is ever checked — never a name taken from a step.
ClassMethod IsInstalled(type As %String) As %Boolean
{
    Quit ..ClassIsInstalled(..GetTargetClass(type))
}

/// A class counts as installed when it is compiled and extends %SYS.Task.Definition.
ClassMethod ClassIsInstalled(className As %String) As %Boolean
{
    Quit:(className = "") 0
    Quit:'##class(%Dictionary.CompiledClass).%ExistsId(className) 0
    Quit ''$CLASSMETHOD(className, "%Extends", "%SYS.Task.Definition")
}

}
