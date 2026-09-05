# Keyed Timers

Feature ID: `04_02_keyed_timers`. Status: implemented within the tested scope.

## Added feature

An example Plugin replaces one keyed timer, ignores stale generations, and flushes one ordered batch. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.BurstBuncher

{:ok, server} = Jido.start_agent(jido, BurstBuncher)
BurstBuncher.add_item(server, "item-1", %{value: 3})
```

## Evidence

4 enabled tests:

- maximum size flushes one ordered batch after commit.
- a later item replaces the pending timeout.
- stale timer generations cannot drain a newer batch.
- a duplicate item ID does not enter the batch twice.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_02_keyed_timers --seed 0
```

[Source](../../../../lib/examples/04_runtime/04_02_keyed_timers/burst_buncher.ex) ·
[Tests](../../../../test/examples/04_runtime/04_02_keyed_timers/burst_buncher_test.exs)

## Boundary and next question

Keyed one-shot replacement is example code. Scheduler has no matching built-in operation.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
