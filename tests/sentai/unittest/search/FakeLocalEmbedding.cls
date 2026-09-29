/// Spec 017 T008: the in-process provider, pointed at the test-only worker.
/// 
/// The worker class is a compile-time parameter of this subclass — never a name read from a row,
/// a request or any other input (Constitution II). Everything else, including how every worker
/// condition becomes a reason, is `sentai.search.LocalEmbedding`'s own code.
/// 
/// Test-only by construction: it lives under `tests/`, and nothing in `src/` names it.
Class sentai.unittest.search.FakeLocalEmbedding Extends sentai.search.LocalEmbedding
{

Parameter WorkerClass = "sentai.unittest.search.FakeEmbeddingWorker";

}
