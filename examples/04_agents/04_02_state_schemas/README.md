# 04_02 State Schemas

A typed Agent accepts profile and count commands without duplicating its state
rules inside each Action.

## What you will learn

- How Action input schemas validate Signal data.
- How route defaults use a shallow merge.
- How the Agent schema validates the complete candidate state.

## Read the code

Read [the Agent and its state contract](typed_command_agent.ex) first. Then read
[the behavior tests](typed_command_agent_test.exs).

## Run it

Run this command from the `jido` repository root:

```sh
mix test.examples examples/04_agents/04_02_state_schemas --warnings-as-errors
```

Expected result: the tests complete without failures. Direct and live execution
produce the same profile, and an out-of-range candidate does not commit.

## Important behavior

Invalid Action input and invalid candidate state leave committed state
unchanged. A later valid command can still commit.

Accepted Server calls return `{:ok, %Jido.AgentServer.TurnResult{}}`. A commit
has the status `:committed`. Invalid Action input and invalid complete state
return a Turn result with `status: :failed` and a `Jido.Error.ValidationError`
in `error`. An invalid complete state uses the code `:invalid_state`.
The tests wait for `Server.await_ready/1` before reading the initial snapshot.

## Limits

This example does not define routing-error policy, Plugin state, or Directive
effects. The profile merge is shallow, not recursive.

## Files

- [Agent and state contract](typed_command_agent.ex)
- [Behavior tests](typed_command_agent_test.exs)

Previous: [Agent Definition](../04_01_agent_definition/README.md) | Next: [Route Selection](../04_03_route_selection/README.md)
