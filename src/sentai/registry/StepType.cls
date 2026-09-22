/// Closed, compiled catalog of the seven step types supported in v1 (FR-037).
/// Data, not code branches (Constitution II) — no value here comes from runtime
/// configuration or operator input. See specs/003-backend-objectscript/data-model.md
/// §Step-type registry.
Class sentai.registry.StepType Extends %RegisteredObject
{

XData Catalog [ MimeType = application/json ]
{
[
  { "type": "integrity-check",     "class": "%SYS.Task.IntegrityCheck",     "category": "verification", "destructive": false, "pausable": false },
  { "type": "compact-globals",     "class": "%SYS.Task.CompactGlobals",     "category": "storage",      "destructive": false, "pausable": false },
  { "type": "defragment-globals",  "class": "%SYS.Task.Defragment",         "category": "storage",      "destructive": false, "pausable": false },
  { "type": "switch-journal",      "class": "%SYS.Task.SwitchJournal",      "category": "journal",      "destructive": false, "pausable": false },
  { "type": "purge-audit-records", "class": "%SYS.Task.PurgeAuditDatabase", "category": "purge",        "destructive": true,  "pausable": true  },
  { "type": "purge-task-history",  "class": "%SYS.Task.PurgeTaskHistory",   "category": "purge",        "destructive": true,  "pausable": true  },
  { "type": "custom",              "class": "",                            "category": "custom",       "destructive": false, "pausable": false }
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

/// Whether pause is supported for the type in v1 — true only for the purge family
/// (the fixed "Pause: purge family only" decision).
ClassMethod IsPausable(type As %String) As %Boolean
{
    Set entry = ..Lookup(type)
    If (entry = "") Quit 0
    Quit entry.pausable
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

/// True if the given type is one of the seven closed values.
ClassMethod IsKnownType(type As %String) As %Boolean
{
    Quit (..Lookup(type) '= "")
}

}
