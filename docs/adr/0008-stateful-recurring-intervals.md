# ADR 0008: Keep stateful recurring intervals in Timer

- Status: Accepted
- Date: 2026-11-14

## Context

The bundled Timer owns recurring cron definitions, timer reconciliation,
generation metadata, and future-timer recovery. Applications also need a
fixed-delay recurring Signal that they can pause and resume without removing
its definition. A common case is one static periodic Signal that starts with
the Agent.

A separate Cycle Plugin can hold this lifecycle state, but it must still use
Timer timers. It duplicates schedule ownership and cannot recover a chain
of runtime-only one-shot timers after Timer or AgentServer replacement.

The former Heartbeat Plugin also owns a fixed-delay timer. Keeping that engine
would give the package two timer runtimes with different state and recovery
rules.

Timer must not become an owner of Agent work, work completion, retry,
acknowledgement, or missed-work replay.

## Decision

Add fixed-delay interval definitions to `Jido.Plugin.Timer`. Keep cron and
interval definitions in Timer Agent state. Each interval definition has a
`running` or `paused` status. Add public Every, Pause, and Resume Directives.
Pause and Resume apply only to intervals. Cancel applies to both recurring
kinds.

Let static Timer Agent options create one running interval definition. Keep
the standard periodic Signal defaults for this declaration. Remove
`Jido.Plugin.Heartbeat` and its runtime. Direct periodic Signal users to Timer.

An active interval produces one Signal after a full interval and then starts
one next full interval. Resume and runtime restore also start a full interval.
Timer does not replay intervals that passed while it was offline. Interval
occurrences use the existing generation and occurrence metadata.

Keep the existing cron-only delivery-adapter contract unchanged. Reject an
active interval when an external delivery adapter is configured. External
interval delivery needs a separate design.

## Consequences

- Agents need only Timer for controlled recurring timer lifecycle.
- A static Timer declaration starts periodic Signal production without a
  control Action.
- Periodic input has one public API and one timer engine.
- Saved cron-only Timer state remains valid.
- Existing cron-only delivery adapters remain valid.
- Interval schedules can recover future timers after runtime replacement.
- Fixed-delay intervals can drift and do not wait for Agent work.
- Applications remain responsible for work results and for rejecting an
  already delivered occurrence from an older generation when needed.

## References

- `Jido.Plugin.Timer`
- `Jido.Plugin.Timer.DeliveryAdapter`
- Covenant component `jido.plugin.timer`
- [Module dependency map](../architecture/module-dependency-map.md)
