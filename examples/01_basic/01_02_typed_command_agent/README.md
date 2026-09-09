# Typed Command Agent

This example accepts a typed profile patch and a typed count command. It teaches
Action input schemas, route defaults, shallow Signal-data merging, and complete
candidate-state validation.

## Read the files

1. Read [the Agent and its state contract](typed_command_agent.ex).
2. Read [the behavior tests](../../../test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs).
3. Read [the shared test case](../../../test/examples/support/basic_sdk_case.ex) for the isolated runtime setup.

## Run the example

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs --include example --seed 0
```

The tests show that direct and live execution produce the same profile. They
also show that the Agent schema rejects a correctly typed count when the final
candidate is outside the allowed bounds.

Invalid Action input and invalid candidate state do not commit. A later valid
command can still commit.

This example does not define routing-error policy, Plugin state, or Directive
effects. The profile default merge is shallow. It is not a recursive merge.

[Previous: Minimal Agent](../01_01_minimal_agent/README.md) · [Back to Basic](../README.md) · [Next: Plugin State Agent](../01_03_plugin_state_agent/README.md)
