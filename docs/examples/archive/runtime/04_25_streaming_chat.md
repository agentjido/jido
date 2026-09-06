> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Streaming Chat

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_25_streaming_chat`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Send partial model output while one Actor turn remains active.
- **User story:** As a user, I see text and tool progress before the final answer commits.
- **Trigger or input:** `chat.stream` Signal with user content.
- **Agent state:** Only final Thread entries, usage, completion reason, and stream summary.
- **Actions or Flow:** One Action or Flow consumes a model event stream and returns the final state.
- **External interactions:** Streaming LLM and client connection. A local contract test replays fixed chunks.
- **Runtime Directives or capabilities:** Jido needs a stable transient progress channel that does not mutate Actor state or create one Directive per token.
- **Expected result:** Clients receive ordered partial events and the final answer commits once.
- **Failure cases:** Disconnect, model error, invalid event order, cancellation, slow consumer, or sensitive chunk.
- **Jido features under pressure:** There is no current public streaming progress contract across an active turn.
- **Source framework and links:** [Google ADK: streaming](https://google.github.io/adk-docs/get-started/streaming/), [Haystack: Agent streaming](https://docs.haystack.deepset.ai/docs/agent), [Pi Agent Core: event subscription](https://github.com/earendil-works/pi/tree/main/packages/agent)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_25_streaming_chat/streaming_chat.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_25_streaming_chat/streaming_chat_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: Direct process messages prove ordered progress. A stable active-Turn progress channel with backpressure is missing.

An example-scope gap is not evidence of a core Jido defect.
