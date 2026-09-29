/// Spec 011 T018: a provider that answers the way `sentai.search.EmbeddingService` answers
/// when a provider accepts the connection and then never responds — past the whole-response
/// budget. It throws the same #10200 status with the same leading `slow:` token, so the
/// service's reason mapping is asserted end to end without making the suite wait out a real
/// timeout and without a network.
///
/// Which transport conditions produce this text is EmbeddingService's own behaviour, covered
/// in `EmbeddingServiceTest`; the double pins only the text it produces.
Class sentai.unittest.search.SlowEmbeddingService Extends %Embedding.Interface
{

ClassMethod IsValidConfig(config As %DynamicObject, ByRef errorMsg As %String) As %Boolean
{
    Set errorMsg = ""
    Quit 1
}

ClassMethod Embedding(input, configuration) As %Vector
{
    $$$ThrowStatus($$$ERROR($$$EmbeddingGeneralError, "slow: no response within 5.0s from test:1"))
    Quit ""
}

}
