# 15_02 Action and Flow tools

Declare an Action and a Flow as model tools. ReAct validates every call, runs
the selected tool as an explicit graph node, and returns the correlated result
to the next model round.

## What you will learn

- How Actions and Flows become registered model tools.
- How per-request policy controls visible tools.

## Read the code

Read [the Agent and tools](agent.ex), then [the tests](tool_flow_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_02_tool_flow --warnings-as-errors
```

Expected result: both tools validate directly, and one deterministic model
round runs the selected Flow tool.

## Important behavior

ReAct runs tool work as explicit graph nodes. It does not call an Action
callback directly.

## Limits

The offline model selects only registered local tools. The example does not
prove remote tool delivery or arbitrary model-generated plans.

## Core Fit and Gaps

Action and Flow tools reuse the normal execution boundary. No separate tool
runtime is required.

## Files

- [Agent and tools](agent.ex)
- [Tests](tool_flow_test.exs)

Previous: [Basic Agent](../15_01_basic_agent/README.md) | Next: [Structured output](../15_03_structured_output/README.md)
