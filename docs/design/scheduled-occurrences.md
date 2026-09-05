> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Scheduled occurrence identity and delivery

Date: **2026-09-04**. Review status: **Pending approval**.

## Implemented boundary

Scheduler can identify a recurring occurrence separately from each Signal
delivery. This is an explicit option on the existing recurring Directive:

```elixir
Scheduler.cron(job_id, cron, tick, generation: generation)
```

The Agent owns the generation in its state. Keep it across restore. Advance it
when replacing or recreating the logical schedule, including after cancellation.
Valid generations are integers from 0 through 2,147,483,647, the positive range
of a CloudEvents context Integer. Scheduler saves the supplied generation with
the recurring definition. It does not allocate generations or retain tombstones.

The runtime uses SchedEx's scheduled DateTime. It hashes a versioned tuple of:

1. Jido instance, Agent ID, and partition.
2. Agent-local job ID.
3. Explicit generation.
4. Scheduled UTC instant in microseconds.

The digest uses SHA-256 over deterministic Erlang external term encoding with
minor version 2. The ID is opaque. Node, PID, arrival time, and Signal ID are
excluded. The coordinates must be portable values. Each delivery still receives
a fresh Signal ID. The same coordinates produce the same occurrence ID.

Moving the Agent to a different node can retain identity if all coordinates
stay the same. A different instance or partition creates a different identity.
This does not provide distributed ownership or a writer lease.

## Signal contract

```elixir
{:ok, occurrence} = Scheduler.occurrence(context.signal)
%Scheduler.Occurrence{id: id, generation: generation, scheduled_at: utc} = occurrence
```

`scheduled_at` is an ISO 8601 UTC string. The Signal carries flat CloudEvents
context attributes `jidooccurrenceid`, `jidoschedulegen`, and `jidoscheduledat`.
These fields do not change domain data, trace context, or user context fields.
Tracked templates cannot supply these reserved attributes. The accessor returns
`{:error, :not_found}` when none exist and a tagged validation error for malformed
or incomplete metadata.

Omitting generation preserves plain ticks and the previous saved definition
shape. Existing schedules do not change to tracked schedules on restore.
One-shot `schedule/2` behavior is unchanged.

## Test clock

The optional Scheduler Plugin configuration `time_scale: Module` accepts the
existing `SchedEx.TimeScale` behavior. It applies to recurring schedules only.
The default uses current time. A named Agent must declare this option in its
definition if it is to use that clock after restore. Clock process state is
not part of the Agent checkpoint.

Core tests use actual SchedEx callbacks, Agent Turns, and file persistence.
The controlled clock can repeat one scheduled instant or advance it across a
crash. It does not generate occurrence IDs or replace the scheduling loop.

## Explicit durable delivery

Add `delivery: :durable` with an explicit generation:

```elixir
Scheduler.cron(job_id, cron, tick, generation: generation, delivery: :durable)
```

Declare `route "jido.scheduler.enqueue", Jido.Plugin.Scheduler.Enqueue` in the
Agent. SchedEx sends this control Signal for each due slot. The Action emits a
Queue Directive. The Scheduler reducer records the pending business Signal in
the Agent's state, and the Server commits that intent before any delivery.

A supervised task reads committed pending work and calls the Agent with a fresh
Signal ID. The occurrence ID stays the same. The business Action returns:

```elixir
{:ok, occurrence} = Scheduler.occurrence(context.signal)
{:ok, next_state, [Scheduler.acknowledge(occurrence.id)]}
```

The acknowledgement removes pending work in the same commit as `next_state`.
A rejected or interrupted commit leaves the pending occurrence available for
retry. A successful commit survives loss of the runtime reply. The `jidodurabletick`
context flag makes Scheduler preparation check the pending identity and payload
before execution. Completed, cancelled, replaced, and altered durable ticks are
rejected. The flag is reserved on schedule templates. It is not an authentication
credential; application admission still controls who can command the Agent.

The saved definition gains `delivery: :durable`, `pending`, and
`last_scheduled_at`. Progress is separate from the runtime job configuration, so
recording or completing a tick does not restart SchedEx. Repeating the same
configuration preserves progress. Replacing an active durable configuration
requires a greater generation. Cancellation removes both definition and pending
work. The application retains its generation counter across cancellation.

## Bounded recovery policy

- Keep at most one pending occurrence per job. The timestamp watermark records
  the latest offered slot, including slots skipped while the job was pending.
- Skip later slots while that job has pending work. Skip slots that pass while
  the Agent is offline. Retry an already committed pending occurrence on restore.
- Retry every 100 milliseconds and rotate through pending jobs. A delivery task
  performs one state read and one Agent call, each with a default five-second
  timeout. The Plugin option `delivery_timeout` changes that call timeout.
- Preserve completion through the Agent checkpoint. An acknowledgement is a
  data Directive; runtime notification only wakes the polling task.

Agent persistence is required to survive Agent or VM loss. A tick lost before
its enqueue intent commits is not retained. Failed business Actions keep their
pending record until a later attempt succeeds or the job is cancelled. External
work can repeat before acknowledgement and must handle duplicate occurrence IDs.
This policy does not implement a catch-up queue, an external-effect transaction,
or distributed storage ownership.

## Plugin restart boundary

The crash tests exposed a wait cycle during Plugin restart: Agent dispatch
waited for a Plugin reference while Plugin readiness waited for Agent state.
Reference lookup now runs inside the existing bounded Directive task. The Agent
can serve the readiness state query while that task waits. Lookup failures and
timeouts still use the existing Directive outcome contract.

See the [REC-03 results](../examples/rec-03-results.md) for the enabled crash,
failed-write, duplicate, cancellation, and generation tests. The document remains
Pending approval under the design review rules.
