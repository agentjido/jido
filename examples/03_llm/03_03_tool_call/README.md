# 03_03 Tool call

This example validates one model-selected tool call before it runs the tool.

## What you will learn

- How a Flow maps an approved tool name to a fixed typed Action.
- How a stable call ID correlates the tool result with the final model call.

## Read the code

Read [the Agent and Flow](tool_call.ex), then the shared
[tool support](../support/tooling.ex) and
[LLM adapter](../support/adapter.ex).

## Run it

```sh
mix test test/examples/03_llm/03_03_tool_call --include example --seed 0
```

Expected result: valid work commits one checked answer. Unknown tools, invalid
arguments, and denied operations make no tool call.

## Important behavior

The complete plan is validated before tool execution. A model string never
becomes a module name. A late model failure preserves Agent state but cannot
undo a tool effect that already finished.

## Limits

The example permits only the local `search` tool and one call per Turn.

## Files

- [Agent and Flow](tool_call.ex)
- [Shared tool support](../support/tooling.ex)
- [Shared LLM adapter](../support/adapter.ex)
- [Tests](../../../test/examples/03_llm/03_03_tool_call/tool_call_test.exs)

Previous: [Conversation History](../03_02_conversation_history/README.md) | Next: [Tool Loop](../03_04_tool_loop/README.md)
