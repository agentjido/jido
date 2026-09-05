> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Multimodal Document Agent

- **ID:** `03_12_multimodal_document_agent`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** true integration

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Answer questions from text, tables, and images in one document.
- **User story:** As a reader, I ask about a chart or table and receive an answer with page evidence.
- **Trigger or input:** `document.multimodal.ask` Signal with document ID and question.
- **Agent state:** Page assets, selected regions, extracted values, answer, and citations.
- **Actions or Flow:** A Flow converts pages, selects relevant regions, calls a multimodal model, and validates citations.
- **External interactions:** Document converter, image store, and multimodal model. Local tests use page fixtures.
- **Runtime Directives or capabilities:** A media Plugin can own temporary asset lifecycle and cleanup.
- **Expected result:** The answer cites the correct page and region and preserves source digests.
- **Failure cases:** Unreadable page, image limit, wrong region, OCR error, model error, or cleanup failure.
- **Jido features under pressure:** Media references, portable state, external assets, size limits, and cleanup.
- **Source framework and links:** [Haystack: multimodal use cases](https://haystack.deepset.ai/), [PydanticAI: multimodal input](https://pydantic.dev/docs/ai/core-concepts/input/)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_12_multimodal_document_agent/multimodal_document_agent.ex`
- `git show 357b22a:test/examples/03_llm/03_12_multimodal_document_agent/multimodal_document_agent_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
