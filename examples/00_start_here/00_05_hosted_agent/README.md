# 00_05 Hosted Agent

Run the same expense behavior as one supervised AgentServer Turn.

## What you will learn

- How to start an Agent in one Jido instance.
- How AgentServer commits valid state and preserves state after failure.

## Read the code

Read [the hosted Agent](hosted_agent.ex), then read the behavior test.

## Run it

```sh
mix test.examples examples/00_start_here/00_05_hosted_agent --warnings-as-errors
```

Expected result: pure and hosted execution produce the same Agent state. A
failed Turn does not change the committed snapshot.

## Important behavior

AgentServer owns process lifecycle and commit. The Agent behavior stays the
same as the pure behavior from the previous lesson.

## Limits

This in-memory Agent does not survive a process or BEAM restart.

## Files

- [Source](hosted_agent.ex)
- [Tests](hosted_agent_test.exs)

Previous: [Routed Agent](../00_04_routed_agent/README.md) |
Next: [Runtime inspection](../00_06_runtime_inspection/README.md)
