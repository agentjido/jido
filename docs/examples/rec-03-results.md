> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# REC-03: scheduled occurrence identity and recovery

Date: **2026-09-04**. Status: **Implemented with explicit durable delivery and a skip policy**.

The previously failing crash test now passes. Scheduler commits a pending
occurrence before business delivery, retries it after restore, and removes it
with the business result commit. There are **25 passing REC-03 tests and no skips**:
12 identity tests, seven pure durable-policy tests, and six runtime recovery tests.

## Use the capability

```elixir
Scheduler.cron("report", "0 * * * *", tick,
  generation: generation,
  delivery: :durable
)
```

Add the explicit control route:

```elixir
routes do
  route "jido.scheduler.enqueue", Jido.Plugin.Scheduler.Enqueue
  route "report.tick", MyApp.HandleReport
end
```

The business Action acknowledges in its returned candidate:

```elixir
{:ok, occurrence} = Scheduler.occurrence(context.signal)
{:ok, next_state, [Scheduler.acknowledge(occurrence.id)]}
```

The [recovery Agent](../../examples/04_runtime/04_13_durable_scheduling/scheduled_occurrence_recovery.ex)
shows registration, the control route, completion, and cancellation. Start it
with an Agent persistence adapter and restore enabled to recover after loss.
The separate [identity probe](../../examples/04_runtime/04_13_durable_scheduling/scheduled_occurrence_probe.ex)
continues to demonstrate metadata without durable delivery.

Generation remains application state: retain it across restore and advance it
on replacement or recreation. Signal data stays unchanged. Existing schedules
without `delivery: :durable` retain their previous behavior and checkpoint shape.

## Recovery proof

```shell
mix test test/jido/plugin/scheduler_occurrence_test.exs test/jido/agent/scheduled_occurrence_test.exs test/jido/plugin/durable_scheduler_test.exs test/jido/agent/scheduled_occurrence_recovery_test.exs --seed 0
```

The original test still holds the real persistence write after the business
Action and before its commit. The barrier now selects that candidate by its
business state, since enqueue adds an earlier intent commit.

1. Register generation 1 and receive the real SchedEx slot at
   `2030-01-01T00:00:01.000000Z`.
2. Commit its pending Signal, then hold the business result write.
3. Confirm that the file contains the pending occurrence and no business result.
4. Kill the Agent, advance the clock, and restore it.
5. Observe the original occurrence ID committed once with a fresh delivery ID.

Other runtime tests cover a crash after the result write, Scheduler process
loss during delivery, failed intent and result writes, and cancellation followed
by restore and recreation. Pure tests cover separate candidate boundaries,
duplicate and altered ticks, generation replacement, old enqueue requests,
unknown acknowledgements, bounded pending state, and skipped busy slots.

The Scheduler restart test also exposed a core wait cycle. Plugin reference
lookup now runs inside the existing bounded dispatch task. The Agent remains
able to answer the restarting Plugin's state query. Agent and Plugin runtime
regression tests pass with this correction.

## Declared policy and limits

Each job keeps one pending occurrence and a timestamp watermark. Later slots
are skipped while that job is pending. Slots missed offline are also skipped;
already committed pending work is retried. Repeating an old or skipped slot does
not create work again. Retry polls run every 100 milliseconds, one job per
attempt, with bounded calls and rotation through pending jobs.

Acknowledgement belongs in the business result commit. Omitting it leaves work
pending and causes repeated attempts. External work before that commit can also
repeat; the receiver must handle duplicate occurrence IDs. Persistence must be
configured for crash recovery. An enqueue request lost before its own commit is
outside the guarantee. Cancellation cannot undo external work already performed.

The tests use real SchedEx callbacks, Agent Turns, and file persistence. The
controlled clock only supplies time. UTC identity normalization is covered;
full daylight-saving scheduling policy and fresh-VM recovery of this Scheduler
capability are not claimed by these tests. Distributed writer authority remains
under DIST-03. See the [design and API note](../design/scheduled-occurrences.md).

## Combined validation

The focused run reports **304 passing tests, no failures or skips**. It includes
all 170 Basic through Multi-agent tests, all implemented research probes, and
Agent runtime, Plugin runtime, and persistence regression tests.

`mix quality` passes, including warnings-as-errors compilation and Dialyzer.
`mix docs --no-open`, local link checks, and Git whitespace checks also pass.
This focused result does not declare the full repository suite green; existing
group, hibernation, and context timing gaps remain in the
[gap register](runtime-multi-agent-gaps.md).
