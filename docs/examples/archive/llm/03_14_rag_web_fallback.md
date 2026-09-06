> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# RAG with Web Fallback

- **ID:** `03_14_rag_web_fallback`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Use web search only when local retrieval has weak evidence.
- **User story:** As a user, I get a current answer when the internal collection is insufficient.
- **Trigger or input:** `rag.ask_current` Signal with question and web policy.
- **Agent state:** Local results, evidence grade, web results, answer, citations, and source route.
- **Actions or Flow:** A Flow grades local evidence and conditionally calls a web adapter before answer generation.
- **External interactions:** Retriever, web search, and LLM. The local test uses fixtures for all three.
- **Runtime Directives or capabilities:** An Audit Directive can record that external search was used.
- **Expected result:** The answer shows whether evidence came from local data, the web, or both.
- **Failure cases:** Policy blocks web, web timeout, bad citation, source conflict, or no evidence.
- **Jido features under pressure:** Fallback policy, external access, source provenance, and transparent degraded results.
- **Source framework and links:** [Haystack: agentic pipelines and web fallback](https://docs.haystack.deepset.ai/docs/pipelines)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_14_rag_web_fallback/rag_web_fallback.ex`
- `git show 357b22a:test/examples/03_llm/03_14_rag_web_fallback/rag_web_fallback_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
