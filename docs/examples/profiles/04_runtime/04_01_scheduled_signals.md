# Scheduled Signals

Feature ID: `04_01_scheduled_signals`. Status: implemented within the tested scope.

## Added feature

A Scheduler Directive produces a later Signal and a separate commit. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.ScheduledCounter

{:ok, server} = Jido.start_agent(jido, ScheduledCounter)
ScheduledCounter.schedule_once(server, 10)
```

## Evidence

3 enabled tests:

- a scheduling Directive starts a later Signal and second Turn.
- CRON Directives add and remove Scheduler runtime state.
- invalid timer and CRON requests leave Agent and Plugin state unchanged.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_01_scheduled_signals --seed 0
```

[Source](../../../../lib/examples/04_runtime/04_01_scheduled_signals/scheduled_counter.ex) ·
[Tests](../../../../test/examples/04_runtime/04_01_scheduled_signals/scheduled_counter_test.exs)

## Boundary and next question

Keyed timer replacement is the next example. Wall-clock due time is not controlled by a public clock adapter.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
