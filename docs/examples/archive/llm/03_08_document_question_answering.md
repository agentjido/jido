> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Document Question Answering

- **ID:** `03_08_document_question_answering`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Answer a question only from supplied documents.
- **User story:** As a reader, I ask about a document set and receive an answer with citations.
- **Trigger or input:** `documents.question` Signal with query and collection ID.
- **Agent state:** Query, retrieved chunk IDs, answer, citations, and confidence warning.
- **Actions or Flow:** A Flow retrieves chunks, builds context, calls the model, and validates citations.
- **External interactions:** Retriever and LLM. Local tests use fixed chunks and replies.
- **Runtime Directives or capabilities:** None for the query. An Audit Directive can store retrieval metadata after commit.
- **Expected result:** Each answer citation maps to a retrieved fixture chunk.
- **Failure cases:** No evidence, retriever timeout, model error, invalid citation, or context limit.
- **Jido features under pressure:** Retrieval adapter, grounding, provenance, state size, and structured output.
- **Source framework and links:** [LlamaIndex: Q&A over data](https://docs.llamaindex.ai/en/stable/understanding/putting_it_all_together/q_and_a/)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_08_document_question_answering/document_question_answering.ex`
- `git show 357b22a:test/examples/03_llm/03_08_document_question_answering/document_question_answering_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
