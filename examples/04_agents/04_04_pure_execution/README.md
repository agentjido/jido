# 04_04 Pure Agent execution

Evaluate one complete Agent Turn without starting a process or committing state.

## What you will learn

- `Agent.cmd/3` routes the Signal and runs the selected Flow.
- Success returns a new candidate Agent value.
- Validation failure returns no candidate and cannot change the source value.

## Read the code

Read [the pure counter](pure_counter.ex) first.

## Run it

`mix test.examples examples/04_agents/04_04_pure_execution --warnings-as-errors`

Expected result: count 2 produces candidate count 5. The source stays at 2.

## Important behavior

Pure evaluation does not commit state, dispatch Directives, save data, or own a
process lifecycle. AgentServer adds those runtime contracts in Chapter 6.

## Limits

An Action can still run application code with its own side effects. The pure
claim applies to the Jido Agent evaluation boundary.

## Files

- [Source](pure_counter.ex)
- [Tests](pure_counter_test.exs)

Previous: [Route selection](../04_03_route_selection/README.md) | Next: [Replies and Directives](../04_05_replies_and_directives/README.md)

