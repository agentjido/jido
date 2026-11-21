# 00_04 Routed Agent

Route one expense Signal to the triage Flow and return a new Agent value.

## What you will learn

- How an Agent route selects a Flow from a Signal type.
- How `Agent.cmd/3` evaluates a Turn without a process.

## Read the code

Read [the Agent and Flow](routed_agent.ex), then read the behavior test.

## Run it

```sh
mix test.examples examples/00_start_here/00_04_routed_agent --warnings-as-errors
```

Expected result: valid input returns a submitted candidate and invalid input
leaves the source Agent unchanged.

## Important behavior

The source and candidate are separate Agent values. Pure evaluation does not
commit state or run AgentServer effects.

## Limits

This lesson does not start or supervise an Agent process.

## Files

- [Source](routed_agent.ex)
- [Tests](routed_agent_test.exs)

Previous: [Triage Flow](../00_03_triage_flow/README.md) |
Next: [Hosted Agent](../00_05_hosted_agent/README.md)
