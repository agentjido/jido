# 00_03 Triage Flow

Compose submission and review classification in one deterministic Flow.

## What you will learn

- How a Flow calls a named Action and an inline step.
- How data dependencies and explicit output define the result.

## Read the code

Read [the Flow](triage_flow.ex), then read the behavior test.

## Run it

```sh
mix test.examples examples/00_start_here/00_03_triage_flow --warnings-as-errors
```

Expected result: a small expense gets automatic review and a large expense
gets manual review.

## Important behavior

The Flow is still a value execution. It does not start an Agent process.

## Limits

The Flow does not yet receive a Signal or commit Agent state.

## Files

- [Source](triage_flow.ex)
- [Tests](triage_flow_test.exs)

Previous: [Submit Action](../00_02_submit_action/README.md) |
Next: [Routed Agent](../00_04_routed_agent/README.md)
