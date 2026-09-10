# 03_04 Tool loop

This example runs a bounded ReAct model-and-tool loop in one Agent Turn.

## What you will learn

- How Flow Dispatch and executable continuations select the next Action.
- How several external calls can lead to one terminal Agent commit.

## Read the code

Read [the Agent](react_agent.ex), [the data contracts](contracts.ex),
[the Flow and Actions](reason_flow.ex), and [the client ports](ports.ex). Finish with the
[local adapters](support/adapters.ex).

## Run it

```sh
mix test test/examples/03_llm/03_04_tool_loop --include example --seed 0
```

Expected result: model and tool rounds produce one committed transcript, while
failed or cancelled work does not commit partial state.

## Important behavior

Model and tool calls occur during Flow execution because each result selects
the next step. Completed external effects remain after a later failure. The
application model-step limit bounds the loop.

## Limits

The loop is sequential and local. It does not persist intermediate rounds or
resume a failed loop.

## Files

- [Agent](react_agent.ex)
- [Data contracts](contracts.ex)
- [Flow and Actions](reason_flow.ex)
- [Model and tool ports](ports.ex)
- [Local adapters](support/adapters.ex)
- [Tests](../../../test/examples/03_llm/03_04_tool_loop/react_agent_test.exs)

Previous: [Tool Call](../03_03_tool_call/README.md) | Next: [Parallel Tools](../03_05_parallel_tools/README.md)
