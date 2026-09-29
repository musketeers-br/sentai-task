/// Spec 011: the one value semantic step-type search answers with, in both directions
/// (Constitution IV — a predictable failure crosses layers as a value, never as an exception).
///
/// There are exactly two shapes and they are mutually exclusive by construction:
///
///   available    {"available":true,  "matches":[{"type":..,"score":..}, …]}
///   unavailable  {"available":false, "reason":"not-configured"|"unreachable"|"slow"
///                                                      |"incompatible"|"error"}
///
/// An `unavailable` outcome cannot carry a partial ranking (FR-025) and a ranking cannot carry a
/// reason: both are built by these constructors, and nothing here throws. Degradation is a **200**
/// (R-007) — the product's answer when search is unusable is today's working palette, so an error
/// status would manufacture the error state the specification forbids (SC-004).
Class sentai.search.SearchOutcome Extends %RegisteredObject
{

/// The reasons an outcome can be unavailable, in the order FR-024 lists them. `error` is the
/// catch-all for anything that is not one of the four named provider conditions; it exists so a
/// failure is still a value rather than a leak, and is never shown to the operator as a message.
Parameter REASONS = "not-configured,unreachable,slow,incompatible,error";

/// A ranked answer. `matches` is already filtered to the floor and already ordered best first
/// (the caller owns that ordering; this type does not re-sort and cannot invent a `type`).
ClassMethod Available(matches As %DynamicArray) As %DynamicObject
{
    Set outcome = {}
    Do outcome.%Set("available", 1, "boolean")
    Do outcome.%Set("matches", $S($IsObject(matches):matches, 1:[]))
    Quit outcome
}

/// The empty ranking — a valid answer meaning "nothing in the catalog is close" (FR-008), which
/// is not the same thing as unavailable.
ClassMethod NoMatches() As %DynamicObject
{
    Quit ..Available([])
}

/// An answer that says search could not rank. `reason` is normalized to one of `REASONS`: an
/// unrecognized value becomes `error` rather than travelling to the frontend, so a provider
/// added later cannot widen the contract by accident.
ClassMethod Unavailable(reason As %String) As %DynamicObject
{
    Set outcome = {}
    Do outcome.%Set("available", 0, "boolean")
    Do outcome.%Set("reason", ..NormalizeReason(reason))
    Quit outcome
}

/// Constrains a reason to the closed list; "" and anything unrecognized are `error`.
ClassMethod NormalizeReason(reason As %String) As %String
{
    Set reason = $ZCONVERT(reason, "l")
    Set n = 1, found = 0
    For i = 1:($L(..#REASONS) > 0) {
        Set piece = $P(..#REASONS, ",", i)
        If piece = "" Quit
        If piece = reason Set found = 1 Quit
    }
    Quit:found reason
    Quit "error"
}

/// True when the outcome is a usable ranking. `available` is a JSON boolean, so it is read as a
/// number, not as an objectref.
ClassMethod IsAvailable(outcome As %DynamicObject) As %Boolean
{
    Quit $IsObject(outcome) && outcome.%IsDefined("available") && (+outcome.available = 1)
}

/// The ranked matches of an outcome, or an empty array when it is unavailable. Callers that do not
/// care about the difference (a caller with today's palette as its fallback) use this and never
/// branch on the reason.
ClassMethod Matches(outcome As %DynamicObject) As %DynamicArray
{
    If '..IsAvailable(outcome) Quit []
    Quit $S(outcome.%IsDefined("matches") && $IsObject(outcome.matches):outcome.matches, 1:[])
}

}
