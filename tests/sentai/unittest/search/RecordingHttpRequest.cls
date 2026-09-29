/// Spec 011 T017: the HTTP transport double for `sentai.search.EmbeddingService`, in the
/// AdminApiDouble pattern — a test-only class that records what it was asked to send and
/// scripts an answer, so a test asserts the request shape with no socket at all.
///
/// It answers the way a *refused connection* answers: Post reports an error status and never
/// sets HttpResponse, so the provider's own code decides the classification and the test
/// reads it off the thrown status rather than off the double. The formal spec mirrors
/// %Net.HttpRequest's own Post, because that is the signature the provider calls.
Class sentai.unittest.search.RecordingHttpRequest Extends %Net.HttpRequest
{

Method Post(location As %String = "", test As %Integer = 0, reset As %Boolean = 1, resetHeaderOnRedirect As %Boolean = 0) As %Status
{
    Do ..EntityBody.Rewind()
    Set ^sentaiEmbeddingDouble("post", "location") = location
    Set ^sentaiEmbeddingDouble("post", "body") = ..EntityBody.Read()
    Quit 0
}

/// Test helper: wipes the recordings, so a run can never read a previous one's request.
ClassMethod ResetRecording() As %Status
{
    Kill ^sentaiEmbeddingDouble
    Quit $$$OK
}

}
