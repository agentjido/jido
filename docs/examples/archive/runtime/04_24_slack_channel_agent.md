> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Slack Channel Agent

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_24_slack_channel_agent`
- **Status:** implemented
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Receive channel messages, run a bounded agent, and post threaded replies.
- **User story:** As a team member, I mention the agent in Slack and receive a correlated result.
- **Trigger or input:** Slack event from an input Plugin.
- **Agent state:** Channel and thread IDs, processed event IDs, Thread state, task status, and reply timestamp.
- **Actions or Flow:** One Flow classifies the request, uses tools, and creates the reply.
- **External interactions:** Slack API, LLM, and optional coding tools. Local tests use recorded event fixtures.
- **Runtime Directives or capabilities:** Input Plugin sends Signals. A Slack Plugin Directive posts the reply after commit.
- **Expected result:** One Slack event creates one reply in the correct thread.
- **Failure cases:** Retry delivery, deleted thread, auth error, rate limit, tool error, or reply failure.
- **Jido features under pressure:** Input Plugin, deduplication, correlation, external write idempotency, and Thread state.
- **Source framework and links:** [PydanticAI: Slack lead qualifier](https://pydantic.dev/docs/ai/examples/slack-lead-qualifier/), [Mastra: Slack agent template](https://mastra.ai/docs)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_24_slack_channel_agent/slack_channel_agent.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_24_slack_channel_agent/slack_channel_agent_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
