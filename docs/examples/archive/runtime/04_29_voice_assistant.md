> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Realtime Voice Assistant

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_29_voice_assistant`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Maintain a low-latency voice session with tools and interruption.
- **User story:** As a caller, I speak naturally, interrupt the assistant, and receive spoken results.
- **Trigger or input:** Audio frames, speech events, tool results, and connection events.
- **Agent state:** Session metadata, final transcript entries, tool outcomes, and connection status.
- **Actions or Flow:** Finite Actions handle semantic events. Media streaming stays in a supervised runtime.
- **External interactions:** Realtime model, audio input and output, and client connection.
- **Runtime Directives or capabilities:** A realtime Plugin owns connection, media stream, interruption, and cleanup commands.
- **Expected result:** Final transcript and tool state commit without storing raw transient audio in Actor state.
- **Failure cases:** Disconnect, codec error, interruption race, tool timeout, model error, or resource leak.
- **Jido features under pressure:** High-rate runtime input, transient media, backpressure, interruption, and cleanup.
- **Source framework and links:** [PydanticAI: realtime voice assistant](https://pydantic.dev/docs/ai/examples/realtime/realtime-voice/), [Mastra: voice](https://mastra.ai/docs/voice/overview)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_29_voice_assistant/voice_assistant.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_29_voice_assistant/voice_assistant_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Semantic transcript events work. A supervised realtime media connection with backpressure and cleanup is not implemented.

An example-scope gap is not evidence of a core Jido defect.
