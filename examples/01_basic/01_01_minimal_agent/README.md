# Minimal Agent

A small Agent keeps a counter and changes it through one typed Signal route.

## What you will learn

- How to declare Agent state and an inline Action.
- How route defaults and generated command helpers work.
- How direct and live execution use the same Agent contract.

## Read the code

Read [the Agent](minimal_agent.ex) first. Then read
[the behavior tests](../../../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs)
and [the shared test setup](../../../test/examples/support/basic_sdk_case.ex).

## Run it

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs --include example --seed 0
```

Expected result: the tests complete without failures. They show default and
explicit increments, unchanged state after invalid input, and separate state
for two Agent instances.

## Important behavior

An invalid amount does not change committed state. A later valid command can
still commit. Direct execution does not change the live Agent Server.

## Limits

This example does not teach Plugins, Directives, persistence, or concurrent
Turns.

## Files

- [Agent source](minimal_agent.ex)
- [Behavior tests](../../../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs)
- [Shared test setup](../../../test/examples/support/basic_sdk_case.ex)

Previous: [Basic overview](../README.md) | Next: [Typed Command Agent](../01_02_typed_command_agent/README.md)
