# 15_04 Limits and tool policy

Use ordinary Jido Actions for local admission checks. Use ReAct `limits` and
the request `tool_policy` for model calls, tool rounds, elapsed time, and tool
visibility. This is the current graph-first control surface.

## What you will learn

- How an Action performs local admission before inference.
- How explicit limits and tool policy bound a ReAct request.

## Read the code

Read [the controlled Agent](agent.ex), then [the tests](controls_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_04_controls --warnings-as-errors
```

Expected result: allow and deny paths are explicit, limits normalize, and a
request can disable all tools.

## Important behavior

Controls are normal Action and request data, not hidden middleware.

## Limits

These are per-request bounds. Jido does not add a hidden cross-request circuit
breaker, provider router, or tenant authorization policy.

## Files

- [Controlled Agent](agent.ex)
- [Tests](controls_test.exs)

Previous: [Structured output](../15_03_structured_output/README.md) | Next: [Streaming](../15_05_streaming/README.md)
