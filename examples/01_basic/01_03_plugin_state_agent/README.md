# Plugin State Agent

This example adds state that a Plugin owns. It teaches Plugin state declaration,
Plugin updates, atomic domain and Plugin commits, and state-ownership protection.

## Read the files

1. Read [the Agent and CountTurns Plugin](plugin_state_agent.ex).
2. Read [the behavior tests](../../../test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs).
3. Read [the shared test case](../../../test/examples/support/basic_sdk_case.ex) for the isolated runtime setup.

## Run the example

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs --include example --seed 0
```

The first command commits the domain count and the Plugin turn count together.
The public snapshot and Plugin-state APIs show the same commit.

An Action cannot overwrite Plugin-owned state. Invalid Plugin output also
rejects the complete candidate. Both failures keep the last committed state,
and a valid command can recover after an ownership failure.

The Plugin allows only one committed Turn so that the failure is deterministic.
This artificial limit is not a recommended application policy. This example
does not teach Plugin processes or Directive dispatch.

[Previous: Typed Command Agent](../01_02_typed_command_agent/README.md) · [Back to Basic](../README.md) · [Next: Directive Agent](../01_04_directive_agent/README.md)
