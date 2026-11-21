# 15_01 Basic AI Agent

Select ReAct, a direct model name, and instructions in the `ai` block. The
Agent definition stores these values as typed reasoning defaults.

## What you will learn

- How `Jido.AI.Agent` adds typed model and reasoning defaults.
- How one offline request commits correlated reply and Session data.

## Read the code

Read [the Agent](agent.ex), then [the tests](basic_agent_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_01_basic_agent --warnings-as-errors
```

Expected result: one deterministic request returns a correlated reply and
commits the Session.

## Important behavior

The local inference client follows the same request boundary as a provider
client.

## Limits

The deterministic client proves request, reply, and Session behavior. It does
not measure a live model or provider.

## Files

- [Agent](agent.ex)
- [Tests](basic_agent_test.exs)

Previous: [Durable Agents](../../13_durable_execution/README.md) |
Next: [Action and Flow tools](../15_02_tool_flow/README.md).
