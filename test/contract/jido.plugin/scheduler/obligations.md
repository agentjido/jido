---
modules:
  - Jido.Plugin.Scheduler
  - Jido.Plugin.Scheduler.Agent
  - Jido.Plugin.Scheduler.Cancel
  - Jido.Plugin.Scheduler.Cron
  - Jido.Plugin.Scheduler.CronRules
  - Jido.Plugin.Scheduler.DSL
  - Jido.Plugin.Scheduler.DSL.Schedule
  - Jido.Plugin.Scheduler.DeliveryAdapter
  - Jido.Plugin.Scheduler.Occurrence
  - Jido.Plugin.Scheduler.Runtime
  - Jido.Plugin.Scheduler.Schedule
  - Jido.Plugin.Scheduler.Server
  - Jido.Plugin.Scheduler.WallClock
---

## Purpose

Protect the bundled Scheduler Plugin's delayed and recurring Signal timers.
The component owns recurring schedule definitions, cron rules, generations,
logical occurrence metadata, timer reconciliation, restart recovery, and clock
validation.

The component does not own generic Plugin callbacks, Agent work, durable
storage, durable business delivery, delivery replay, or acknowledgement.

The public boundary is `Jido.Plugin.Scheduler`, its `Schedule`, `Cron`, and
`Cancel` Directives, `Occurrence` data, and the separate static-authoring
`DSL`, and `DeliveryAdapter`. Agent state, runtime, server, wall-clock, and DSL
entity modules are internal. The runtime Plugin uses the standard Plugin
configuration and adds no custom DSL section.

## Obligations

### jido.plugin.scheduler.I1 — Owned schedule state

- **scope:** `Jido.Plugin.Scheduler`, `Jido.Plugin.Scheduler.Agent`, `Jido.Plugin.Scheduler.Schedule`, `Jido.Plugin.Scheduler.Cron`, `Jido.Plugin.Scheduler.Cancel`
- **must:** Expose constructors and validated types for Schedule, Cron, and Cancel Directives. Keep only recurring definitions in the owned Agent state, apply valid Cron and Cancel Directives in list order, and keep one-shot timers out of Agent state.
- **kind:** functional
- **status:** active

### jido.plugin.scheduler.I2 — Input and compatibility boundary

- **scope:** `Jido.Plugin.Scheduler`, `Jido.Plugin.Scheduler.Agent`, `Jido.Plugin.Scheduler.Schedule`, `Jido.Plugin.Scheduler.Cron`, `Jido.Plugin.Scheduler.Cancel`, `Jido.Plugin.Scheduler.DeliveryAdapter`
- **must:** Accept only `timezone` and `generation` as unique `cron/4` options. Reject invalid delays, cron rules, timezones, generations, nonportable definitions, unknown or duplicate constructor options, invalid delivery adapters, and saved definitions with retired delivery fields. Keep durable storage, admission, delivery, and acknowledgement outside the Scheduler API.
- **kind:** functional
- **status:** active

### jido.plugin.scheduler.I3 — Static schedule authoring

- **scope:** `Jido.Plugin.Scheduler.DSL`, `Jido.Plugin.Scheduler.DSL.Schedule`
- **must:** Accept either schedule DSL entities or Plugin data but not both, normalize exactly one interval or five-, six-, or seven-field cron timing form, default omitted schedules and Signal data to empty collections, apply the UTC timezone default, reject duplicate names and live Signal template values, and require a matching Agent input route with a schedule-scoped error.
- **kind:** functional
- **status:** active

### jido.plugin.scheduler.I4 — One-shot timer delivery

- **scope:** `Jido.Plugin.Scheduler.Runtime`
- **must:** Without a delivery adapter, start one runtime-only timer after a valid Schedule Directive, send one fresh Signal when its current token fires, derive its trace from the source Signal, ignore stale tokens, and cancel remaining timers when the runtime stops. With a delivery adapter, send the delayed occurrence to that adapter and start no local timer.
- **kind:** ordering
- **status:** active

### jido.plugin.scheduler.I5 — Recurring timer reconciliation

- **scope:** `Jido.Plugin.Scheduler.Runtime`
- **must:** Without a delivery adapter, reconcile timers to the latest committed recurring definitions, retain equal live jobs, replace changed or dead jobs, cancel removed jobs, ignore stale state versions and stale tick tokens, and send each current tick as a fresh Signal. With a delivery adapter, reconcile the committed definitions through that adapter and start no local recurring timer.
- **kind:** functional
- **status:** active

### jido.plugin.scheduler.I6 — Logical occurrence identity

- **scope:** `Jido.Plugin.Scheduler`, `Jido.Plugin.Scheduler.Occurrence`, `Jido.Plugin.Scheduler.Runtime`
- **must:** For a schedule with a generation, derive one stable occurrence ID from the Jido instance, Agent ID, partition, job ID, generation, and UTC slot. Preserve Signal data and other context, reject reserved or malformed metadata, and keep plain schedules untagged.
- **kind:** functional
- **status:** active

### jido.plugin.scheduler.I7 — Timer recovery and dormant schedules

- **scope:** `Jido.Plugin.Scheduler.Runtime`, `Jido.Plugin.Scheduler.Server`
- **must:** Restore future recurring timers from committed Agent state after Scheduler, Agent, or job replacement. Keep a valid finite schedule with no future slot dormant without blocking other schedules.
- **kind:** functional
- **status:** active

### jido.plugin.scheduler.I8 — Failure and retry containment

- **scope:** `Jido.Plugin.Scheduler.Runtime`, `Jido.Plugin.Scheduler.Server`
- **must:** Fail startup before readiness when state or clock validation fails, return structured runtime errors, contain adapter exceptions and invalid results, retry the latest committed recurring definition set with one owned timer and its state version, keep stale retry work inert, and recover when the cause is removed.
- **kind:** functional
- **status:** active

### jido.plugin.scheduler.I9 — Clock and readiness rules

- **scope:** `Jido.Plugin.Scheduler.Agent`, `Jido.Plugin.Scheduler.Runtime`, `Jido.Plugin.Scheduler.Server`, `Jido.Plugin.Scheduler.WallClock`
- **must:** Own exactly the AgentServer options `delivery_adapter`, `retry_delay_ms`, and `time_scale`; reject unknown or duplicate Plugin options; and accept only a valid delivery adapter, valid time-scale module, and bounded positive retry delay. Wait for each positive wall-clock remainder with upward millisecond rounding, permit shutdown cancellation, and report readiness only after initial reconciliation.
- **kind:** functional
- **status:** active
