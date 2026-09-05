> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Single-Tool Agent

- **ID:** `03_17_single_tool_agent`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Show the smallest model-selected tool call.
- **User story:** As a user, I ask a factual question and the agent chooses one allowed tool.
- **Trigger or input:** `agent.ask` Signal with a short question.
- **Agent state:** Question, tool call, tool result, final answer, and model usage.
- **Actions or Flow:** A Flow calls a fake model, validates one tool call, runs the tool, and asks for the final response.
- **External interactions:** Model and one tool adapter. Both are fake in the local test.
- **Runtime Directives or capabilities:** None are required for synchronous execution.
- **Expected result:** The final answer includes the tool result and one complete state commit.
- **Failure cases:** Unknown tool, invalid arguments, tool error, model error, or extra tool call.
- **Jido features under pressure:** Tool schema, model message conversion, Action effect, usage data, and loop bound.
- **Source framework and links:** [Haystack: Agent](https://docs.haystack.deepset.ai/docs/agent), [Google ADK: multi-tool quickstart](https://google.github.io/adk-docs/get-started/quickstart/)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_17_single_tool_agent/single_tool_agent.ex`
- `git show 357b22a:test/examples/03_llm/03_17_single_tool_agent/single_tool_agent_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
