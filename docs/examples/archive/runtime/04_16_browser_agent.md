> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Browser Agent

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_16_browser_agent`
- **Status:** implemented
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Complete a bounded web task with visible browser state.
- **User story:** As a user, I ask the agent to navigate a site and collect or submit allowed data.
- **Trigger or input:** `browser.task` Signal with goal, allowed origins, and action budget.
- **Agent state:** Goal, browser observations, action log, extracted result, and terminal status.
- **Actions or Flow:** A ReAct Flow chooses browser actions and validates each action against policy.
- **External interactions:** Browser automation and LLM. Local contract tests use a fake page model.
- **Runtime Directives or capabilities:** A Browser Plugin can own session start, navigation, screenshot, and cleanup runtime commands.
- **Expected result:** The task stops within budget and records the final page and extracted result.
- **Failure cases:** Blocked origin, changed page, selector failure, login request, unsafe action, timeout, or cleanup failure.
- **Jido features under pressure:** Long-lived resource Plugin, effectful tools, security policy, progress, and cleanup.
- **Source framework and links:** [Mastra: Browser Agent template](https://mastra.ai/docs), [PydanticAI: Browser Use](https://pydantic.dev/docs/ai/harness/browser-use/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_16_browser_agent/browser_agent.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_16_browser_agent/browser_agent_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
