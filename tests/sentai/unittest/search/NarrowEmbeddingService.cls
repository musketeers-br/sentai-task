/// Spec 011 T018: the same bag-of-words vector as FakeEmbeddingService but half as wide, so a
/// corpus stored by the standard double cannot be ranked against it. VECTOR_COSINE across
/// widths yields no score at all — measured: SQLCODE 0 with the mismatched row simply absent
/// — which is exactly the state the service must report as `incompatible` rather than as an
/// empty ranking, because an empty ranking looks like "no results" and is the masquerade
/// FR-023 exists to forbid.
///
/// The corpus is untouched by the swap (descriptions still match), so this exercises the
/// provider-swap-without-rebuild path the story describes.
Class sentai.unittest.search.NarrowEmbeddingService Extends sentai.unittest.search.FakeEmbeddingService
{

Parameter Dimensions = 128;

}
