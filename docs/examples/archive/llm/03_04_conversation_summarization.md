> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Conversation Summarization

- **ID:** `03_04_conversation_summarization`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Keep long conversation context within a fixed budget.
- **User story:** As a user, I continue a long chat without losing key decisions and facts.
- **Trigger or input:** `thread.compact` Signal or a chat Signal that crosses a size threshold.
- **Agent state:** Application-owned entries, summary, preserved facts, compacted range, and source digest.
- **Actions or Flow:** A Flow selects old entries, summarizes them, verifies required facts, and replaces the compacted range.
- **External interactions:** LLM summarizer. Local tests use a deterministic summary adapter.
- **Runtime Directives or capabilities:** The Action returns the complete next Actor state. A schedule can run maintenance later.
- **Expected result:** The summary covers required facts and new context stays below the limit.
- **Failure cases:** Fact loss, summary too large, concurrent new message, model error, or invalid range.
- **Jido features under pressure:** Actor-owned history, large state, optimistic version, model validation, and maintenance Signals.
- **Source framework and links:** [Sagents: Summarization middleware](https://sagents.hexdocs.pm/api-reference.html), [Pi Agent Core: message replacement](https://github.com/earendil-works/pi/tree/main/packages/agent)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_04_conversation_summarization/conversation_summarization.ex`
- `git show 357b22a:test/examples/03_llm/03_04_conversation_summarization/conversation_summarization_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
