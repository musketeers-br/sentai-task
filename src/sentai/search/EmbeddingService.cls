/// Spec 011: the embedding provider the search feature adds to the platform's own
/// `%Embedding.Config` table (data-model.md §5). One row in the platform's table names this class,
/// so **nothing here is hardcoded** — host, port, `https`, `path`, `model` and an optional
/// `apiKey` are all read from the row's `Configuration` JSON (FR-011). Pointing a deployment at a
/// different provider is a change to that row, never to this class (FR-012).
///
/// It speaks the OpenAI-compatible `POST /v1/embeddings` shape, which is what the local Ollama
/// service in the dev compose stack serves and what a hosted provider serves too (research R-003).
/// There is no reference to `api.openai.com`, and no SSL configuration is required for the
/// default, which is a plain-HTTP service on the compose network.
///
/// The query text leaves this process inside the request body and is never written anywhere
/// (FR-010). Note the trade-off a hosted provider brings, documented in README.md (FR-012).
Class sentai.search.EmbeddingService Extends %Embedding.Interface
{

/// Seconds to wait for the whole response. A provider slower than this is a specified state
/// ("slow"), not a hang: the search service maps the platform's timeout to a reason instead of
/// blocking a keystroke (research R-013).
Parameter RequestTimeout = 5;

/// Seconds to wait for the connection alone, so an unreachable host fails fast rather than
/// consuming the whole request budget.
Parameter OpenTimeout = 3;

/// The port assumed when the configuration gives none. 11434 is Ollama's published port; it is
/// a default for a missing field, not a hardcoded endpoint — a row may name any port.
Parameter DefaultPort = 11434;

/// Validates a `%Embedding.Config` row's `Configuration` object, called by that table's own
/// validating trigger, so a malformed row is rejected at insert time with this message rather
/// than at the operator's first keystroke (research R-002).
///
/// Requires `host`, `path` and `model`; `port`, `https` and `apiKey` are optional.
ClassMethod IsValidConfig(config As %DynamicObject, ByRef errorMsg As %String) As %Boolean
{
    If ('$IsObject(config)) || ($L(config.%Get("host")) = 0) {
        Set errorMsg = "host not set"
        Quit 0
    }
    If $L(config.%Get("path")) = 0 {
        Set errorMsg = "path not set"
        Quit 0
    }
    If $L(config.%Get("model")) = 0 {
        Set errorMsg = "model not set"
        Quit 0
    }
    Set errorMsg = ""
    Quit 1
}

/// The request this configuration describes. Pure — it opens no connection — so a test can assert
/// that the endpoint really comes from the row and not from a constant in this file.
ClassMethod NewRequest(config As %DynamicObject) As %Net.HttpRequest
{
    Set req = ##class(%Net.HttpRequest).%New()
    Set req.Server = config.%Get("host")
    Set req.Port = ..PortOf(config)
    Set req.Https = (+config.%Get("https") = 1)
    Set req.ContentType = "application/json"
    Set req.ContentCharset = "UTF-8"
    Set req.Timeout = ..#RequestTimeout
    Set req.OpenTimeout = ..#OpenTimeout
    // Only sent when the row carries a key. The default (local Ollama) needs none, and this is
    // where a hosted provider's credential enters — from the row, never from the code.
    If $L(config.%Get("apiKey")) > 0 {
        Do req.SetHeader("Authorization", "Bearer "_config.%Get("apiKey"))
    }
    Quit req
}

/// The endpoint path the row names, normalized to a leading slash.
ClassMethod Endpoint(config As %DynamicObject) As %String
{
    Set path = config.%Get("path")
    // The first character is compared, not the whole string: `[` means "contains anywhere", and
    // let a row's "v1/embeddings" through unnormalized — a defect T017's transport case caught.
    If $EXTRACT(path, 1) = "/" Quit path
    Quit "/"_path
}

/// The port the row names, or DefaultPort when it names none.
ClassMethod PortOf(config As %DynamicObject) As %Integer
{
    Set port = +config.%Get("port")
    Quit $S(port > 0:port, 1:..#DefaultPort)
}

/// Embeds one input, as the platform's `EMBEDDING()` requires of a provider named in
/// `%Embedding.Config`. Returns a %Vector of the provider's own numbers.
///
/// Failures are thrown as statuses, which is how the platform expects a provider to report them;
/// `sentai.search.StepSearchService` catches them and turns each into a reason on the answer,
/// never into a 5xx (Constitution IV, R-007).
ClassMethod Embedding(input As %String, configuration As %String) As %Vector
{
    Set config = [].%FromJSON(configuration)
    Set req = ..NewRequest(config)

    // An interpolated object literal in a call argument is a compile-time error in ObjectScript,
    // so the body is built and then serialized (research R-001a).
    Set body = ##class(%DynamicObject).%New()
    Set body.model = config.%Get("model")
    Set body.input = $S($IsObject(input):input.%ToJSON(), 1:input)
    Do req.EntityBody.Write(body.%ToJSON())

    // Whether the *connection* was even established, decided by how long the attempt took: a
    // provider that refused or could not be named failed at once, while a provider that accepted
    // the connection and then went quiet ran into the open-timeout budget. This is the only place
    // the timing is observable, so `slow` is decided here and travels on the error text.
    Set started = $ZTIMESTAMP
    Set sc = req.Post(..Endpoint(config))

    // A request that never reached the provider leaves no response object at all, so the HTTP
    // status is only read once one is known to exist. Measured empirically on IRIS 2026.2: a
    // transport failure leaves StatusCode empty and Post returns 0, while a 200 returns 1 with
    // StatusCode 200 — the HTTP status is the reliable signal, so `sc` is not trusted to mean
    // success.
    Set statusCode = 0, response = ""
    If $IsObject(req.HttpResponse) {
        Set response = req.HttpResponse
        Set statusCode = +response.StatusCode
    }

    If statusCode = 0 {
        // Whether the *connection* was even established is decided by how long the attempt took: a
        // provider that refused or could not be named failed at once, while a provider that
        // accepted the connection and then went quiet ran into the open-timeout budget. This is the
        // only place the timing is observable, so `slow` is decided here and travels on the text.
        Set spent = $ZTIMESTAMP - started
        Set origin = config.%Get("host")_":"_..PortOf(config)
        If (spent >= ..#OpenTimeout) {
            Set detail = "slow: no response within "_spent_"s from "_origin
            $$$ThrowStatus($$$ERROR($$$EmbeddingGeneralError, detail))
        }
        Set detail = "unreachable: no response from "_origin
        $$$ThrowStatus($$$ERROR($$$EmbeddingGeneralError, detail))
    }

    If statusCode '= 200 {
        // The provider answered, but not with an embedding. Its own status line and body are
        // preserved verbatim; the leading `error` token is what the service maps to a reason.
        Set detail = "error: "_response.StatusLine_" "_response.Data
        $$$ThrowStatus($$$ERROR($$$EmbeddingApiError, "provider", detail))
    }

    Set parsed = {}.%FromJSON(response.Data)
    If ('$IsObject(parsed)) || ('$IsObject(parsed.data)) || (parsed.data.%ToJSON() = "[]") {
        $$$ThrowStatus($$$ERROR($$$EmbeddingApiError, "provider", "error: provider returned no embedding"))
    }

    Quit ..ToVector(parsed.data.%Get(0).embedding)
}

/// The provider's JSON array of numbers as a %Vector.
///
/// The components are read from the array's JSON text rather than through a cursor: this build of
/// %DynamicArray exposes no iterator and no index accessor, while %ToJSON() hands back exactly the
/// bracketed, comma-separated form that %Library.Vector converts. A component that is not a number
/// is a provider defect and is reported, never silently coerced to a zero — a silently-zeroed
/// component would rank a real entry against a meaningless vector.
ClassMethod ToVector(raw) As %Vector
{
    If '$IsObject(raw) {
        $$$ThrowStatus($$$ERROR($$$EmbeddingGeneralError, "provider returned an embedding that is not a list of numbers"))
    }
    // %DynamicArray in this build exposes no iterator and no index accessor, so the array's own
    // JSON text is used instead: %ToJSON() returns exactly the bracketed, comma-separated form
    // that %Library.Vector converts, and it needs no per-element access to do so.
    Set rawText = $REPLACE($REPLACE(raw.%ToJSON(), "[", ""), "]", "")
    If rawText = "" {
        $$$ThrowStatus($$$ERROR($$$EmbeddingGeneralError, "provider returned an empty embedding"))
    }
    // A component that is not a number is a provider defect and is reported, never silently
    // coerced to a zero — a silently-zeroed component would rank a real entry against a
    // meaningless vector. $TRANSLATE leaves behind whatever the float characters and the
    // component separator cannot account for, so any residue means at least one component was
    // not a number.
    If $TRANSLATE(rawText, "0123456789.,-+eE", "") '= "" {
        Set residue = $TRANSLATE(rawText, "0123456789.,-+eE", "")
        Set detail = "provider returned a non-numeric embedding component, unrecognised "_residue
        $$$ThrowStatus($$$ERROR($$$EmbeddingGeneralError, detail))
    }
    Quit ##class(%Library.Vector).DisplayToLogical("[" _ rawText _ "]")
}

}
