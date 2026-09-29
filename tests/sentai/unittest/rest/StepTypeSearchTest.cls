/// Spec 011 T010 / US1: the `GET /catalog/step-types/search` route (contracts/api-delta.md).
/// Written before `Dispatcher.SearchStepTypes` existed (Principle V).
///
/// What is asserted here is the route's own behaviour: which status it answers with, and whether the
/// service is reached at all. The shape of the payload is the service's business and is asserted in
/// `sentai.unittest.search.StepSearchServiceTest`, so this class does not re-test the ranking — that
/// is the house split between an endpoint test and the service behind it.
Class sentai.unittest.rest.StepTypeSearchTest Extends sentai.unittest.SentaiTestCase
{

/// The captured row, or "" when there was none. Deliberately %RawString: an object-typed
/// property coerces "" into an oref-shaped value, and "no row at all" — the state CI runs in,
/// with no %Embedding.Config row on the instance — must survive the capture/restore round-trip
/// (found by the T034 gate, 2026-09-28).
Property SavedProvider As %RawString;

Method OnBeforeOneTest() As %Status
{
    Set sc = ##super()
    Do ##class(sentai.unittest.search.SearchFixtures).ClearCorpus()
    Set ..SavedProvider = ##class(sentai.unittest.search.SearchFixtures).CaptureProvider()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).InstallFakeProvider()
    Do $$$AssertEquals(problem, "", "the test double is installed as the configured provider row")
    Quit sc
}

Method OnAfterOneTest() As %Status
{
    Set sc = ##super()
    Do ##class(sentai.unittest.search.SearchFixtures).ClearCorpus()
    Set problem = ##class(sentai.unittest.search.SearchFixtures).RestorePlatformProvider(..SavedProvider)
    Do $$$AssertEquals(problem, "", "the platform's own provider row is put back")
    Quit sc
}

/// Calls the route with `q` set to the given text, and leaves the response in `%response`.
/// An empty `argument` is a **missing** `q`, not an empty one, which is the case the palette can
/// never produce and the case a careless reader of "blank" would skip.
///
/// The parameter is written straight into `%request.Data`, the property `%request.Get` reads: the
/// class has no `Parameters` list on this build (R-014).
Method CallSearch(text As %String = "", include As %Boolean = 1) As %Status
{
    Set %request = ##class(%CSP.Request).%New()
    If include Set %request.Data("q", 1) = text
    Set %response = ##class(%CSP.Response).%New()
    Quit ##class(sentai.rest.Dispatcher).SearchStepTypes()
}

/// FR-005, contracts §400: `q` absent, empty or whitespace is a `400` and the service is never
/// reached. A `q` that is only whitespace is the interesting one — it is not empty, so a test that
/// only checked `""` would let it through as a real question and spend a provider call on it.
Method TestBlankQueryIsRejectedBeforeTheServiceIsReached()
{
    Set before = ##class(sentai.unittest.search.SearchFixtures).CorpusRowCount()

    // Whitespace is spelled with `$CHAR`, not `$TAB`: `$TAB` does not exist on this build (R-014).
    For text = "", "   ", ($CHAR(9)_" "_$CHAR(9,10)) {
        Set include = (text '= "")
        Do ..CallSearch(text, include)
        Do $$$AssertEquals(%response.Status, 400, "a blank q is not a question")
    }

    // A blank `q` reaching the service would embed it and build a corpus; the count not moving is
    // what proves nothing downstream ran. The real-query test below is what makes it observable.
    Do $$$AssertEquals(##class(sentai.unittest.search.SearchFixtures).CorpusRowCount(), before, "no corpus was built, so no provider was called")
}

/// The control for the assertion above: the same route with a real `q` does reach the service, so a
/// corpus appears. Without this the "count did not move" assertion could pass for the wrong reason.
Method TestARealQueryReachesTheService()
{
    Set before = ##class(sentai.unittest.search.SearchFixtures).CorpusRowCount()
    Do ..CallSearch("free up disk space")
    Do $$$AssertEquals(%response.Status, 200)
    Do $$$AssertTrue(##class(sentai.unittest.search.SearchFixtures).CorpusRowCount() > before, "a real q builds the corpus, which is the proof the blank-q case leans on")
}

/// FR-001: a real question is answered `200` and the answer is the service's own, not a projection
/// the Dispatcher reshaped. The route delegates and writes; the ranking is not its business.
Method TestRankedSearchIsServedAsTwoHundred()
{
    Do ..CallSearch("check globals and reclaim space")
    Do $$$AssertEquals(%response.Status, 200)

    Set outcome = ##class(sentai.search.StepSearchService).Search("check globals and reclaim space")
    Do $$$AssertTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome), "the double is installed, so the search is answered")
    Set matches = ##class(sentai.search.SearchOutcome).Matches(outcome)
    Do $$$AssertTrue(matches.%Size() > 0, "the query matched something to serve")
    // The floor is the API's, applied before the wire: nothing below it is ever written.
    Do $$$AssertTrue(matches.%Get(0).score >= 0.2, "the first match is at or above the floor")
}

/// R-007, FR-024, SC-004: a provider that is not configured is a **`200`**, not a `503` and not a
/// `500`. The product's answer when search is unavailable is today's working palette, so an error
/// status would manufacture the very error state the specification forbids.
Method TestUnavailableSearchIsServedAsTwoHundredNotAnErrorStatus()
{
    Do ##class(sentai.unittest.search.SearchFixtures).RemoveProvider()
    Do ..CallSearch("free up disk space")
    Do $$$AssertEquals(%response.Status, 200, "a degraded provider is a 200")
}

/// FR-025: the unavailable body carries no `matches` key at all. Asserted on the object the route
/// writes, because `WriteJSON` serializes the outcome as it is given — a key on the object is a key
/// on the wire, and a partial ranking must never reach the frontend as a partial answer.
Method TestUnavailableOutcomeCarriesNoMatches()
{
    Do ##class(sentai.unittest.search.SearchFixtures).RemoveProvider()
    Set outcome = ##class(sentai.search.StepSearchService).Search("free up disk space")
    Do $$$AssertNotTrue(##class(sentai.search.SearchOutcome).IsAvailable(outcome))
    Do $$$AssertNotTrue(outcome.%IsDefined("matches"), "an unavailable outcome has no matches key")
    Do $$$AssertEquals(##class(sentai.search.SearchOutcome).NormalizeReason(outcome.reason), "not-configured")
}

}
