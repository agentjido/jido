# Plugin State Agent

An Agent and a Plugin update their separate state fields in one atomic commit.

## What you will learn

- How a Plugin declares and updates the state that it owns.
- How domain state and Plugin state commit together.
- How Jido prevents an Action from changing Plugin-owned state.

## Read the code

Read [the Agent and its `CountTurns` Plugin](plugin_state_agent.ex) first. Then
read [the behavior tests](../../../test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs).

## Run it

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs --include example --seed 0
```

Expected result: the tests complete without failures. A valid Turn commits both
state owners, and invalid ownership or Plugin output does not commit.

## Important behavior

An Action cannot overwrite Plugin-owned state. Invalid Plugin output rejects
the complete candidate. A valid command can recover after an ownership failure.

## Limits

The Plugin permits only one committed Turn to make its failure deterministic.
This artificial limit is not an application policy. The example does not teach
Plugin processes or Directive dispatch.

## Files

- [Agent and Plugin source](plugin_state_agent.ex)
- [Behavior tests](../../../test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs)
- [Shared test setup](../../../test/examples/support/basic_sdk_case.ex)

Previous: [Typed Command Agent](../01_02_typed_command_agent/README.md) | Next: [Directive Agent](../01_04_directive_agent/README.md)
