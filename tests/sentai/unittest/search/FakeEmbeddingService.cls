/// Spec 011 T007: a test-only embedding provider, so the search tests can assert an exact ranking
/// with no network and no model.
///
/// It is a **bag of words over a fixed number of buckets**: each word is hashed to a bucket and
/// counted, and `VECTOR_COSINE` then measures how much vocabulary a query and a description share.
/// Two texts with no word in common land in unrelated buckets, so the ranking a test asserts is
/// produced by the same arithmetic every run — no tolerance, no flakiness, no provider involved.
///
/// Test-only by construction: it lives under `tests/`, and nothing in `src/` names it. Tests point
/// a `%Embedding.Config` row at this class and delete the row afterwards, which is also how the
/// `not-configured` case is exercised.
Class sentai.unittest.search.FakeEmbeddingService Extends %Embedding.Interface
{

/// Buckets in the vector. A corpus of nine descriptions cannot fill 256, and a wider vector means
/// fewer words land in the same bucket by accident.
Parameter Dimensions = 256;

/// Accepts any configuration. The real provider's validation is
/// `tests/sentai/unittest/search/EmbeddingServiceTest.cls`'s subject; a double that rejected rows
/// would only make every test that installs one more verbose.
ClassMethod IsValidConfig(config As %DynamicObject, ByRef errorMsg As %String) As %Boolean
{
    Set errorMsg = ""
    Quit 1
}

/// The platform's entry point. The configuration is ignored on purpose: this provider has no
/// endpoint, which is the point of it.
ClassMethod Embedding(input, configuration) As %Vector
{
    Set text = $S($IsObject(input):input.%ToJSON(), 1:input)
    Quit ..Of(text)
}

/// The vector for any text: word counts in hashed buckets, serialized for
/// `%Library.Vector.DisplayToLogical`, which is the same conversion the real provider uses.
ClassMethod Of(text As %String) As %Vector
{
    Set counts = ##class(%DynamicArray).%New()
    For i = 1:1:(..#Dimensions) { Do counts.%Push(0) }
    Set normalized = $ZCONVERT(text, "l"), word = "", words = 0
    For i = 1:1:($LENGTH(normalized) + 1) {
        // The code, not the character, is what is compared: a pattern or a collation comparison
        // on a single character is build-dependent, and this has to be the same on every machine.
        // The extra iteration past the end of the text is what flushes the last word.
        Set code = $ASCII($EXTRACT(normalized, i))
        If ((code >= 97) && (code <= 122)) || ((code >= 48) && (code <= 57)) {
            Set word = word_$EXTRACT(normalized, i)
        } Else {
            If (word '= "") {
                Set bucket = (..Bucket(word) - 1)
                Do counts.%Set(bucket, (+counts.%Get(bucket)) + 1)
                Set words = words + 1
                Set word = ""
            }
        }
    }
    // Text with no words in it still has to produce a vector cosine can divide: a single unit
    // component keeps the arithmetic defined, and matches nothing else meaningfully.
    If (words = 0) { Do counts.%Set(0, 1) }
    // %ToJSON() hands back exactly the bracketed, comma-separated form the vector type converts,
    // so no per-element access is needed to serialize it.
    Quit ##class(%Library.Vector).DisplayToLogical("["_counts.%ToJSON()_"]")
}

/// Which bucket a word belongs in. A fixed multiply-and-add over the word's characters, so the
/// same word always lands in the same bucket on every machine and every run.
///
/// The loop is written in the three-argument `start:increment:stop` form, and the stop is
/// parenthesized, on purpose: on this platform build a two-argument `For i = 1:$LENGTH(word)`
/// silently runs forever, because a bare stop expression is not read as a bound (research R-014).
ClassMethod Bucket(word As %String) As %Integer
{
    Set h = 5381
    For i = 1:1:($LENGTH(word)) {
        Set h = ((h * 33) + $ASCII(word, i)) # 1048573
    }
    Quit (h # ..#Dimensions) + 1
}

}
