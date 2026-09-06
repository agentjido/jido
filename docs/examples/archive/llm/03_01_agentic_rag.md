> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Agentic RAG

- **ID:** `03_01_agentic_rag`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Let the model decide when retrieval is needed and correct a weak query.
- **User story:** As a user, I receive a grounded answer even when my first query is poor.
- **Trigger or input:** `rag.ask` Signal with a user question.
- **Agent state:** Question versions, retrieval decisions, graded documents, answer, and iteration count.
- **Actions or Flow:** A bounded Flow can retrieve, grade, rewrite the question, retrieve again, and answer.
- **External interactions:** LLM, embedding model, and vector store. Local tests use fixed decisions and documents.
- **Runtime Directives or capabilities:** None are required in the local synchronous form.
- **Expected result:** The agent answers from graded evidence or gives a clear no-evidence result.
- **Failure cases:** Rewrite loop, retrieval error, invalid grade, context limit, or ungrounded answer.
- **Jido features under pressure:** Conditional loops, model tool decisions, bounded state, and typed termination.
- **Source framework and links:** [LangGraph: custom agentic RAG](https://docs.langchain.com/oss/python/langgraph/agentic-rag)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_01_agentic_rag/agentic_rag.ex`
- `git show 357b22a:test/examples/03_llm/03_01_agentic_rag/agentic_rag_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
