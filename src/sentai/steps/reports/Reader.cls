/// Spec 013: reads the management API of the one instance a report step runs on (the primary, or
/// the target at `baseUrl`) with the run's credential for it. The only thing a report class may do
/// with the platform: `GET` a fixed path (plan D-5, Constitution II/III).
Class sentai.steps.reports.Reader Extends %RegisteredObject
{

Property BaseUrl As %String(MAXLEN = 512);

Property Token As %String(MAXLEN = "");

/// Number of reads made, for the report's summary.
Property Reads As %Integer [ InitialExpression = 0 ];

ClassMethod For(baseUrl As %String, token As %String) As sentai.steps.reports.Reader
{
    Set reader = ..%New()
    Set reader.BaseUrl = baseUrl, reader.Token = token
    Quit reader
}

/// `GET path`. On success returns the answer's `result` (object or array) and sets `problem` to "";
/// otherwise returns "" and sets `problem` to the platform's words, verbatim:
///   "Administrative endpoint <path> returned HTTP <status>: <summary>" (as the platform steps do),
///   or "Target did not answer: <transport error>".
/// Spec 020: `errorId` is the platform's own id of its first status error (for example
/// `OAuth2NoConfiguration`), "" when there is none — so a report can tell a state from a refusal.
Method Get(path As %String, Output problem As %String, Output errorId As %String)
{
    Set problem = "", errorId = "", httpStatus = 0, location = "", transportError = ""
    Set ..Reads = ..Reads + 1
    Set body = ##class(sentai.dispatch.AdminApiClient).Get(path, ..Token, .httpStatus, .location, ..BaseUrl, .transportError)
    If (transportError '= "") {
        Set problem = $S(..BaseUrl '= "":"Target did not answer: ", 1:"The platform did not answer: ")_transportError
        Quit ""
    }
    If (httpStatus '= 200) || '$IsObject(body) {
        Set summary = $S($IsObject(body) && $IsObject(body."status"):body."status"."summary", 1:"")
        If $IsObject(body) && $IsObject(body."status") && $IsObject(body."status"."errors") && (body."status"."errors".%Size() > 0) {
            Set first = body."status"."errors".%Get(0)
            Set:$IsObject(first) errorId = first.id
        }
        Set problem = "Administrative endpoint "_path_" returned HTTP "_httpStatus_$S(summary '= "":": "_summary, 1:"")
        Quit ""
    }
    Quit body."result"
}

}
