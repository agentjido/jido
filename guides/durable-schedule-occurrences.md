# Durable Schedule Occurrences

The Scheduler can store one pending occurrence per recurring job in
Plugin-owned Agent state. This supports explicit retry after loss.

## Create A Durable Cron Directive

```elixir
tick =
  Jido.Signal.new!(
    "reports.tick",
    %{job_id: "hourly"},
    source: "/reports/scheduler"
  )

directive =
  Jido.Plugin.Scheduler.cron(
    "hourly",
    "0 * * * *",
    tick,
    generation: 1,
    delivery: :durable
  )
```

Declare `Jido.Plugin.Scheduler` and add a route for
`"jido.scheduler.enqueue"` to `Jido.Plugin.Scheduler.Enqueue`.

## Follow The Protocol

1. The runtime detects a due UTC slot.
2. An enqueue Turn stores one pending occurrence.
3. The runtime sends the business Signal in a later Turn.
4. Business work reads the occurrence metadata.
5. The successful result returns an acknowledgement Directive.
6. The same commit updates business state and clears pending work.

Read occurrence data with:

```elixir
with {:ok, occurrence} <-
       Jido.Plugin.Scheduler.occurrence(context.signal) do
  {:ok, next_state,
   [Jido.Plugin.Scheduler.acknowledge(occurrence.id)]}
end
```

## Use Stable Identity

Occurrence identity includes the Jido instance, Agent ID, partition, job ID,
generation, and scheduled UTC instant. It excludes arrival time, node, PID, and
Signal ID.

Use a new generation when you replace or recreate one logical schedule. Use the
occurrence ID as the external idempotency key when business work can repeat.

## Know The Limits

The Scheduler keeps at most one pending occurrence per job. It skips later
slots while that occurrence is pending and skips other slots while the system
is offline. It does not replay every missed wall-clock slot.

`delivery_interval` controls attempts to send saved work. `delivery_timeout`
limits one state read and delivery call. These settings do not change identity
or acknowledgement rules.

Agent persistence is required if pending state must survive a complete Jido or
VM loss. See [Persistence Adapters](persistence-adapters.livemd) and
[Recoverable Effects](recoverable-effects.md).
