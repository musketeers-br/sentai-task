/// Spec 011 T017 / US2: the provider the platform's `%Embedding.Config` row names — its
/// validation and the request it issues. Written against the shipped class (T005), whose
/// `NewRequest` is deliberately pure so a test can read the request without a connection;
/// the issued-request case (body and endpoint, not just the request object) uses the
/// AdminApiDouble pattern via RecordingHttpRequest / RecordingEmbeddingService.
///
/// Nothing here installs a provider row or touches the corpus: every method calls the class
/// directly, so this suite is hermetic by construction (research R-001).
Class sentai.unittest.search.EmbeddingServiceTest Extends sentai.unittest.SentaiTestCase
{

/// A configuration with exactly the fields asked for, in the strict JSON the platform's own
/// table demands: `%EMBEDDING.Config` validates the column at insert time and rejects anything
/// that is not strict JSON (R-014). Built as an object rather than a literal for the same
/// reason SearchFixtures builds its own.
ClassMethod CompleteConfig(host As %String, path As %String, model As %String, apiKey As %String = "", port As %Integer = 0) As %DynamicObject
{
    Set cfg = ##class(%DynamicObject).%New()
    Do cfg.%Set("host", host)
    Do cfg.%Set("path", path)
    Do cfg.%Set("model", model)
    If (apiKey '= "") Do cfg.%Set("apiKey", apiKey)
    If (port > 0) Do cfg.%Set("port", port)
    Quit cfg
}

/// FR-011 / research R-002: a malformed row is rejected at insert time — by the table's own
/// validating trigger calling this method — with a message that says what is missing, rather
/// than at the operator's first keystroke.
Method TestIsValidConfigRejectsIncompleteConfiguration()
{
    For field = "host", "path", "model" {
        Set cfg = ..CompleteConfig("provider.example.internal", "/v1/embeddings", "probe-model-12345")
        // An absent field and an empty one read the same through %Get, and the validation
        // treats them the same too — this is the row the table cannot accept.
        Do cfg.%Set(field, "")
        Set errorMsg = ""
        Do $$$AssertNotTrue(##class(sentai.search.EmbeddingService).IsValidConfig(cfg, .errorMsg), "a row without "_field_" is rejected")
        Do $$$AssertTrue($L(errorMsg) > 0, "the rejection says what is missing ("_field_")")
    }
    Set errorMsg = ""
    Do $$$AssertNotTrue(##class(sentai.search.EmbeddingService).IsValidConfig("", .errorMsg), "a row with no configuration object at all is rejected")
    Do $$$AssertTrue($L(errorMsg) > 0, "even the empty row gets a message")
}

Method TestIsValidConfigAcceptsCompleteConfiguration()
{
    Set cfg = ..CompleteConfig("provider.example.internal", "/v1/embeddings", "probe-model-12345")
    Set errorMsg = "left over"
    Do $$$AssertTrue(##class(sentai.search.EmbeddingService).IsValidConfig(cfg, .errorMsg), "host, path and model are all the table requires")
    Do $$$AssertEquals(errorMsg, "", "an accepted row sets no error message")
}

/// FR-011: everything the request object carries comes from the row — including the two
/// timeouts T005 shipped, so "a slow provider is an answer, not a hang" is visible here too.
/// `NewRequest` opens no connection, so the request object itself is the assertion surface.
Method TestRequestIsBuiltFromTheConfiguration()
{
    Set cfg = ..CompleteConfig("provider.example.internal", "v1/embeddings", "probe-model-12345", "secret-1", 8443)
    Do cfg.%Set("https", 1)
    Set req = ##class(sentai.search.EmbeddingService).NewRequest(cfg)
    Do $$$AssertEquals(req.Server, "provider.example.internal", "the host comes from the row, not from a constant")
    Do $$$AssertEquals(req.Port, 8443, "the port comes from the row")
    Do $$$AssertEquals(req.Https, 1, "https comes from the row")
    Do $$$AssertEquals(req.Timeout, 5, "the whole-response budget the class declares")
    Do $$$AssertEquals(req.OpenTimeout, 3, "the connect budget the class declares")
    Do $$$AssertEquals(req.GetHeader("Authorization"), "Bearer secret-1", "the key enters from the row, and only when the row carries one")
    Do $$$AssertEquals(##class(sentai.search.EmbeddingService).Endpoint(cfg), "/v1/embeddings", "the row's path is normalized onto a leading slash")
    // A row without a port gets the default, and a row without a key sends no header at all.
    Set bare = ..CompleteConfig("other.example.internal", "/v1/embeddings", "probe-model-12345")
    Set req2 = ##class(sentai.search.EmbeddingService).NewRequest(bare)
    Do $$$AssertEquals(req2.Port, 11434, "a missing port is a default, not a hardcoded endpoint")
    Do $$$AssertEquals(req2.GetHeader("Authorization"), "", "no key in the row, no header on the wire")
}

/// FR-011, the transport case: the request the class *issues* — body and endpoint — not just
/// the request object it builds. The recording double takes the place of the real
/// %Net.HttpRequest, and everything around it (the body built from the row's configuration,
/// the endpoint from the row's path, the classification of the refusal) is the parent's own
/// inherited code, so what the double records is what the real class sends. No socket opens.
Method TestIssuedRequestCarriesTheRowsModelAndPath()
{
    Do ##class(sentai.unittest.search.RecordingHttpRequest).ResetRecording()
    Set cfg = ..CompleteConfig("provider.example.internal", "v1/embeddings", "probe-model-12345", "secret-1", 8443)
    Set thrown = ""
    Try {
        Do ##class(sentai.unittest.search.RecordingEmbeddingService).Embedding("rotate the journal", cfg.%ToJSON())
        Do $$$AssertTrue(0, "a recording transport never answers, so Embedding always throws here")
    } Catch e {
        // %Exception carries no readable Status property on this platform build — AsStatus()
        // is the accessor (measured on IRIS 2026.2; e.Status raises <PROPERTY DOES NOT EXIST>).
        Set thrown = ##class(%SYSTEM.Status).GetErrorText(e.AsStatus())
    }
    Do $$$AssertTrue(thrown["unreachable", "the parent classifies the recording transport as a refused origin")
    Do $$$AssertTrue(thrown["provider.example.internal:8443", "the classification names the row's host and port, not a constant")
    Do $$$AssertEquals($G(^sentaiEmbeddingDouble("post", "location")), "/v1/embeddings", "the endpoint issued is the row's path, normalized")
    Set body = $G(^sentaiEmbeddingDouble("post", "body"))
    Do $$$AssertTrue($L(body) > 0, "the request body was recorded")
    Do $$$AssertTrue(body["probe-model-12345", "the body names the row's model, not a constant")
    Do $$$AssertTrue(body["rotate the journal", "the body carries the text that was embedded")
    Do ##class(sentai.unittest.search.RecordingHttpRequest).ResetRecording()
}

/// R-013: a provider that refuses the connection is classified `unreachable` fast — measured
/// on a loopback port nothing listens on, which fails in well under the connect budget. The
/// real code path an unreachable host takes runs here, with nothing to wait for.
Method TestRefusedOriginIsClassifiedUnreachable()
{
    Set cfg = ..CompleteConfig("127.0.0.1", "/v1/embeddings", "probe-model-12345", , 1)
    Set thrown = ""
    Try {
        Do ##class(sentai.search.EmbeddingService).Embedding("probe", cfg.%ToJSON())
        Do $$$AssertTrue(0, "a refused origin never yields an embedding")
    } Catch e {
        Set thrown = ##class(%SYSTEM.Status).GetErrorText(e.AsStatus())
    }
    Do $$$AssertTrue(thrown["unreachable", "a refused connection is the unreachable condition")
    Do $$$AssertTrue(thrown["127.0.0.1:1", "the classification names the configured origin")
}

}
