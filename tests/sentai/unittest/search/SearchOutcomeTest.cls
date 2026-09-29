/// Spec 011 T004: the tagged value every layer of search crosses (Constitution IV, FR-024, FR-025).
/// Degradation is a value and a 200, never an exception and never a 5xx (R-007, SC-004).
Class sentai.unittest.search.SearchOutcomeTest Extends sentai.unittest.SentaiTestCase
{

/// The ranked shape serializes exactly as the contract shows it.
Method TestAvailableSerializesAsContract()
{
    Set matches = [{"type": "compact-globals", "score": 0.5294}, {"type": "storage-headroom-check", "score": 0.4967}]
    Set outcome = ##class(sentai.search.SearchOutcome).Available(matches)
    Do $$$AssertEquals(outcome.%ToJSON(), {"available": true, "matches": [{"type": "compact-globals", "score": 0.5294}, {"type": "storage-headroom-check", "score": 0.4967}]}.%ToJSON())
}

/// An empty ranking is a real answer meaning "nothing in the catalog is close" (FR-008) — it is
/// not the same thing as unavailable, and the two must never be confused by a caller.
Method TestEmptyRankingIsAvailableNotUnavailable()
{
    Set outcome = ##class(sentai.search.SearchOutcome).NoMatches()
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "an empty ranking is available")
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).Matches(outcome).%ToJSON(), "[]")
    Do $$$AssertNotTrue(outcome.%IsDefined("reason"), "an available outcome carries no reason")
}

/// Every reason in FR-024 survives verbatim, so the contract's closed list is the one the class
/// produces rather than a list the frontend has to defend against.
Method TestEveryDocumentedReasonIsPreserved()
{
    For reason = "not-configured", "unreachable", "slow", "incompatible", "warming", "error" {
        Set outcome = ##class(sentai.search.SearchOutcome).Unavailable(reason)
        Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), reason)
        Do $$$AssertEquals(outcome.reason, reason)
        Do $$$AssertEquals(outcome.%ToJSON(), {"available": false, "reason": (reason)}.%ToJSON(), reason)
    }
}

/// A reason this class does not know cannot reach the frontend: it is narrowed to `error` rather
/// than widening the contract, so a provider shipped later cannot add a sixth reason by accident.
Method TestUnknownReasonBecomesError()
{
    For reason = "", "teapot", "SLOW" {
        Set outcome = ##class(sentai.search.SearchOutcome).Unavailable(reason)
        Do $$$AssertEquals(outcome.reason, $S(reason = "SLOW": "slow", 1:"error"), reason)
    }
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).NormalizeReason("Unreachable"), "unreachable", "case is normalized")
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).NormalizeReason("nope"), "error")
}

/// FR-025: a partial ranking is never reported. The unavailable shape has no `matches` key at all,
/// so a caller that reads it gets nothing rather than a truncated list to mistake for the truth.
Method TestUnavailableCarriesNoMatches()
{
    Set outcome = ##class(sentai.search.SearchOutcome).Unavailable("unreachable")
    Do $$$AssertNotTrue(outcome.%IsDefined("matches"), "no partial ranking is constructible")
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).Matches(outcome).%ToJSON(), "[]", "reads as empty, not as a ranking")
}

/// `available` is a JSON boolean, so the read is numeric — an objectref comparison would be true
/// for both shapes and quietly invert every degraded branch in the product.
Method TestIsAvailableReadsTheBooleanNumerically()
{
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(##class(sentai.search.SearchOutcome).NoMatches()))
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable(##class(sentai.search.SearchOutcome).Unavailable("slow")))
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable({}), "an object with no available is not available")
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable("nonsense"), "a non-object is not available")
}

/// A caller that does not care about the difference reads one accessor and never branches, which is
/// what keeps today's palette as a working fallback rather than an error state.
Method TestMatchesPassesThroughWhatItWasGiven()
{
    Set given = [{"type": "integrity-check", "score": 0.9}]
    Set outcome = ##class(sentai.search.SearchOutcome).Available(given)
    Set got = ##class(sentai.search.SearchOutcome).Matches(outcome)
    Do $$$AssertEquals(got."0"."type", "integrity-check", "the ranking is handed back, not rebuilt")
    Do $$$AssertEquals(got."0"."score", 0.9)
    // A malformed available outcome still reads as an empty array rather than throwing at a caller.
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).Matches({}).%ToJSON(), "[]")
}

/// Spec 017 FR-004a: `warming` is a reason of its own — the in-process provider is still loading —
/// so it reaches the canvas by name instead of being narrowed to `error`.
Method TestWarmingIsAKnownReason()
{
    Set outcome = ##class(sentai.search.SearchOutcome).Unavailable("warming")
    Do $$$AssertEquals(outcome.reason, "warming")
    Do $$$AssertNotTrue(outcome.%IsDefined("matches"), "an unavailable outcome carries no matches key (FR-025)")
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).NormalizeReason("WARMING"), "warming")
}

}
