/// Spec 011 T017: names the recording transport as the request the provider builds, so the
/// body and endpoint `sentai.search.EmbeddingService` constructs are recorded rather than
/// sent. Everything else is inherited: the body is built from the row's own configuration and
/// the endpoint from the row's own path, by the parent's unmodified code — so what the double
/// records is what the real class issues.
///
/// Test-only by construction: it lives under `tests/`, and nothing in `src/` names it.
Class sentai.unittest.search.RecordingEmbeddingService Extends sentai.search.EmbeddingService
{

ClassMethod NewRequest(config As %DynamicObject) As %Net.HttpRequest
{
    Quit ##class(sentai.unittest.search.RecordingHttpRequest).%New()
}

}
