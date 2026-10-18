# Typed Command Agent

A typed Agent accepts profile and count commands without duplicating its state
rules inside each Action.

## What you will learn

- How Action input schemas validate Signal data.
- How route defaults use a shallow merge.
- How the Agent schema validates the complete candidate state.

## Read the code

Read [the Agent and its state contract](typed_command_agent.ex) first. Then read
[the behavior tests](../../../test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs).

## Run it

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs --include example --seed 0
```

Expected result: the tests complete without failures. Direct and live execution
produce the same profile, and an out-of-range candidate does not commit.

## Important behavior

Invalid Action input and invalid candidate state leave committed state
unchanged. A later valid command can still commit.

Successful Server calls return `{:ok, agent, directives}`. These commands
return no directives, so the last element is `[]`. Invalid Action input
returns `Jido.Action.Error.InvalidInputError`. An invalid complete state
returns `%Jido.Agent.Error{code: :invalid_state, path: [:state]}`.
The tests wait for `Server.await_ready/1` before reading the initial snapshot.

## Limits

This example does not define routing-error policy, Plugin state, or Directive
effects. The profile merge is shallow, not recursive.

## Files

- [Agent and state contract](typed_command_agent.ex)
- [Behavior tests](../../../test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs)

Previous: [Minimal Agent](../01_01_minimal_agent/README.md) | Next: [Plugin State Agent](../01_03_plugin_state_agent/README.md)
