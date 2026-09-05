> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Web Chat UI

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_27_web_chat_ui`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Connect browser sessions to Actor conversations and runtime outcomes.
- **User story:** As a user, I open a web page, send messages, and inspect tool and error events.
- **Trigger or input:** HTTP or WebSocket client messages.
- **Agent state:** Thread, session identity, UI-safe status, and last terminal outcome.
- **Actions or Flow:** One Action or Flow handles each user Signal and returns response state.
- **External interactions:** Web server, WebSocket, browser, and LLM.
- **Runtime Directives or capabilities:** Input Plugin creates Signals. Dispatch and transient progress capabilities send UI events.
- **Expected result:** Reconnect restores the conversation and does not duplicate a submitted message.
- **Failure cases:** Disconnect, duplicate submit, expired session, auth error, backpressure, or unsafe event payload.
- **Jido features under pressure:** Session mapping, input Plugins, streaming contract, Thread persistence, and security.
- **Source framework and links:** [Pi: transport-neutral client](https://github.com/earendil-works/pi/tree/main/packages/client), [Pi: Chord remote WebUI use case](https://github.com/earendil-works/pi/tree/main/packages/chord), [PydanticAI: Web Chat UI](https://pydantic.dev/docs/ai/guides/web/), [LlamaIndex: full-stack application](https://docs.llamaindex.ai/en/stable/understanding/putting_it_all_together/apps/), [Sagents: demo application](https://github.com/sagents-ai/agents_demo)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_27_web_chat_ui/web_chat_ui.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_27_web_chat_ui/web_chat_ui_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The transport-neutral session restores state and rejects duplicate submits. WebSocket input, authentication, and progress delivery are not implemented.

An example-scope gap is not evidence of a core Jido defect.
