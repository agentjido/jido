# 17_01 ReAct tool loop

Run one complete ReAct tool round with deterministic model output.

## What you will learn

- How a `Jido.AI.Agent` routes a request to the ReAct Flow.
- How one model response expands into bounded parallel tool work.

## Read the code

Read [the Agent](simple_agent.ex), then read the test and offline runner.

## Run it

```sh
mix test.examples examples/17_ai_reasoning_flows/17_01_react_tool_loop --warnings-as-errors
mix run examples/17_ai_reasoning_flows/17_01_react_tool_loop/simple_agent.exs
```

Expected result: the runner prints the public ReAct graphs and prepared tools.
The deterministic behavior test requests two tools and commits the final reply
to the Session.

## Important behavior

The test and runner use fixed model results. They do not select a provider or
contact a network service.

## Limits

The example proves one bounded tool round. It does not prove provider behavior,
model quality, or recovery after process loss.

## Core Fit and Gaps

- Logical owner: the AI Agent.
- Process owner: AgentServer for the hosted test.
- Canonical state owner: the AI Agent Session state.
- Commit point: the final successful Agent Turn.
- Persisted data: none.
- Retry boundary: no retry in this example.
- Idempotency rule: tool calls are deterministic but not durable.
- Injected failure: deterministic malformed and failed model results in tests.
- Recovery result: failed work does not commit a final assistant message.
- Non-guarantees: no live provider, durability, or model-quality claim.

The public AI Agent, ReAct, tool, and Session contracts compose without a
private runtime API. The old runner called `ExpandNext.run/2` directly and
failed after its input contract changed. The replacement uses Agent preflight
and leaves the full tool round to `Agent.cmd/3`. This is application-code and
documentation friction, not a missing SDK operation.

## Files

- [Agent](simple_agent.ex)
- [Tests](simple_agent_test.exs)
- [Offline runner](simple_agent.exs)

Next: [Custom reasoning Flow](../17_05_custom_reasoning_flow/README.md)
