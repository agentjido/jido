> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Moderated Group Chat

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_05_group_chat`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Coordinate several role Agents in a shared conversation.
- **User story:** As a user, I observe specialists discuss a problem under a moderator policy.
- **Trigger or input:** User message, participant response, moderator choice, or timeout Signal.
- **Agent state:** Participants, shared Thread, active speaker, moderator decision, round count, and result.
- **Actions or Flow:** A moderator Flow selects speakers and checks completion. Each response is a separate Signal turn.
- **External interactions:** Child model Agents. Local tests use fixed response Actors.
- **Runtime Directives or capabilities:** Child lifecycle, Signal delivery, and timeout commands.
- **Expected result:** One speaker acts at a time and the chat stops with a validated result.
- **Failure cases:** Speaker loop, invalid selection, participant failure, context limit, or moderator timeout.
- **Jido features under pressure:** Shared conversation model, child isolation, speaker policy, Thread size, and stop rules.
- **Source framework and links:** [Semantic Kernel: group chat orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/group-chat)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_05_group_chat/group_chat.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_05_group_chat/group_chat_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: A bounded moderator and local participants work. Separate child reply Signals, timeout, and participant lifecycle are not implemented.

An example-scope gap is not evidence of a core Jido defect.
