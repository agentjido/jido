---
modules:
  - Jido.Plugin.Timer
  - Jido.Plugin.Timer.Cancel
  - Jido.Plugin.Timer.Cron
  - Jido.Plugin.Timer.CronRules
  - Jido.Plugin.Timer.DSL
  - Jido.Plugin.Timer.DSL.Schedule
  - Jido.Plugin.Timer.DeliveryAdapter
  - Jido.Plugin.Timer.Every
  - Jido.Plugin.Timer.Occurrence
  - Jido.Plugin.Timer.Pause
  - Jido.Plugin.Timer.Resume
  - Jido.Plugin.Timer.Runtime
  - Jido.Plugin.Timer.Schedule
  - Jido.Plugin.Timer.Signal.Tick
  - Jido.Plugin.Timer.WallClock
---

## Purpose

Protect the bundled Timer Plugin's delayed and recurring Signal timers.
The component owns cron and fixed-delay interval definitions, recurring
lifecycle state, cron rules, generations, logical occurrence metadata, timer
reconciliation, restart recovery, and clock validation.

The component does not own generic Plugin callbacks, Agent work, durable
storage, durable business delivery, delivery replay, or acknowledgement.

The public boundary is `Jido.Plugin.Timer`, its `Schedule`, `Cron`, `Every`,
`Pause`, `Resume`, and `Cancel` Directives, `Occurrence` data, the separate
static-authoring `DSL`, and `DeliveryAdapter`. The root owns Agent state and
Plugin runtime callbacks. Runtime, validation-rule, wall-clock, and DSL entity
modules are internal. The runtime Plugin uses the standard Plugin
configuration and adds no custom DSL section. Static interval options lower to
the same `every` state used by dynamic interval Directives.

## Obligations

### jido.plugin.timer.I1 — Owned schedule state

- **scope:** `Jido.Plugin.Timer`, `Jido.Plugin.Timer.Schedule`, `Jido.Plugin.Timer.Cron`, `Jido.Plugin.Timer.Every`, `Jido.Plugin.Timer.Pause`, `Jido.Plugin.Timer.Resume`, `Jido.Plugin.Timer.Cancel`
- **must:** Expose constructors and validated types for Schedule, Cron, Every, Pause, Resume, and Cancel Directives. Keep only recurring definitions in owned Agent state, keep interval lifecycle status inside each interval definition, apply valid recurring Directives in list order, preserve old cron-only state through defaults, keep job IDs unique across recurring kinds, and keep one-shot timers out of Agent state. Pause and Resume apply only to interval definitions.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I2 — Input boundary

- **scope:** `Jido.Plugin.Timer`, `Jido.Plugin.Timer.Schedule`, `Jido.Plugin.Timer.Cron`, `Jido.Plugin.Timer.Every`, `Jido.Plugin.Timer.Pause`, `Jido.Plugin.Timer.Resume`, `Jido.Plugin.Timer.Cancel`, `Jido.Plugin.Timer.DeliveryAdapter`
- **must:** Accept only `timezone` and `generation` as unique `cron/4` options and only `generation` as the unique `every/4` option. Reject invalid delays, intervals, cron rules, timezones, generations, nonportable definitions, reserved occurrence metadata, unknown or duplicate constructor options, invalid delivery adapters, and saved definitions with retired delivery fields. Keep durable storage, admission, delivery, and acknowledgement outside the Timer API.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I3 — Static schedule authoring

- **scope:** `Jido.Plugin.Timer.DSL`, `Jido.Plugin.Timer.DSL.Schedule`
- **must:** Accept either schedule DSL entities or Plugin data but not both, normalize exactly one interval or five-, six-, or seven-field cron timing form, default omitted schedules and Signal data to empty collections, apply the UTC timezone default, reject duplicate names and live Signal template values, and require a matching Agent input route with a schedule-scoped error.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I4 — One-shot timer delivery

- **scope:** `Jido.Plugin.Timer.Runtime`
- **must:** Without a delivery adapter, start one runtime-only timer after a valid Schedule Directive, send one fresh Signal when its current token fires, derive its trace from the source Signal, ignore stale tokens, and cancel remaining timers when the runtime stops. With a delivery adapter, send the delayed occurrence to that adapter and start no local timer.
- **kind:** ordering
- **status:** active

### jido.plugin.timer.I5 — Recurring timer reconciliation

- **scope:** `Jido.Plugin.Timer.Runtime`
- **must:** Without a delivery adapter, reconcile timers to the latest committed active cron and fixed-delay interval definitions, retain equal live jobs, replace changed or dead jobs, cancel removed or paused jobs, ignore stale state versions and stale tick tokens, and send each current tick as a fresh Signal. A current interval tick must arm one next full interval after it produces its Signal. With a delivery adapter, reconcile cron definitions through the unchanged callback, reject active intervals, and start no local recurring timer.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I6 — Logical occurrence identity

- **scope:** `Jido.Plugin.Timer`, `Jido.Plugin.Timer.Occurrence`, `Jido.Plugin.Timer.Runtime`
- **must:** For a cron or interval schedule with a generation, derive one stable occurrence ID from the Jido instance, Agent ID, partition, job ID, generation, and UTC slot. Preserve Signal data and other context, reject reserved or malformed metadata, tag interval schedules by default, and keep plain cron schedules untagged.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I7 — Timer recovery and dormant schedules

- **scope:** `Jido.Plugin.Timer.Runtime`, `Jido.Plugin.Timer`
- **must:** Restore future active recurring timers from committed Agent state after Timer, Agent, or job replacement, keep paused intervals paused, start intervals with one full future delay, and do not replay missed occurrences. Keep a valid finite cron schedule with no future slot dormant without blocking other schedules.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I8 — Failure and retry containment

- **scope:** `Jido.Plugin.Timer.Runtime`, `Jido.Plugin.Timer`
- **must:** Fail startup before readiness when state or clock validation fails, return structured runtime errors, contain adapter exceptions and invalid results, retry the latest committed recurring definition set with one owned timer and its state version, keep stale retry work inert, and recover when the cause is removed.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I9 — Clock and readiness rules

- **scope:** `Jido.Plugin.Timer`, `Jido.Plugin.Timer.Runtime`, `Jido.Plugin.Timer.WallClock`
- **must:** Own exactly the AgentServer options `delivery_adapter`, `retry_delay_ms`, and `time_scale`; reject unknown or duplicate Plugin options; and accept only a valid delivery adapter, valid time-scale module, and bounded positive retry delay. Wait for each positive wall-clock remainder with upward millisecond rounding, permit shutdown cancellation, and report readiness only after initial reconciliation.
- **kind:** functional
- **status:** active

### jido.plugin.timer.I10 — Static auto-start interval

- **scope:** `Jido.Plugin.Timer`, `Jido.Plugin.Timer.Signal.Tick`, `Jido.Plugin.Timer.Runtime`
- **must:** Accept Agent-owned `interval`, `signal_type`, `signal_data`, and `source` options. When any static interval option is declared, validate it before Agent instantiation, create one running `every` definition with generation zero, start it through the normal Timer runtime, and send fresh Signals with the configured type, data, and source. Keep a bare Timer declaration free of an implicit interval.
- **kind:** functional
- **status:** active
