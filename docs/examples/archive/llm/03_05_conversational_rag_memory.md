> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Conversational RAG with Memory

- **ID:** `03_05_conversational_rag_memory`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Resolve follow-up questions with conversation context and document evidence.
- **User story:** As a user, I ask a short follow-up and the agent understands its reference.
- **Trigger or input:** `rag.chat` Signal with a session message.
- **Agent state:** An application-owned message list in `thread`, resolved query, retrieved chunks, answer, and memory summary.
- **Actions or Flow:** An Action resolves the query from Actor history, retrieves evidence, and appends a grounded answer.
- **External interactions:** Retriever and LLM. Local tests use fake components.
- **Runtime Directives or capabilities:** The Action returns history as part of the complete next Actor state. No Directive is required.
- **Expected result:** The resolved query is explicit and citations support the answer.
- **Failure cases:** Ambiguous reference, context limit, bad summary, retrieval error, or invalid citation.
- **Jido features under pressure:** Actor-owned history, context compaction, retrieval, correlation, and one commit.
- **Source framework and links:** [Haystack: conversational RAG pattern](https://docs.haystack.deepset.ai/docs/pipelines), [Mastra: memory](https://mastra.ai/docs/memory/overview)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_05_conversational_rag_memory/conversational_rag_memory.ex`
- `git show 357b22a:test/examples/03_llm/03_05_conversational_rag_memory/conversational_rag_memory_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
