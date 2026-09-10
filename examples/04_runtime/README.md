# Runtime examples

These examples move from short-lived runtime work to observation, recovery,
and durable scheduling. Each example uses deterministic local services and
public Jido APIs.

## Learning order

1. [Scheduled Signals](04_01_scheduled_signals/README.md) — emit later work with Scheduler Directives.
2. [Keyed Timers](04_02_keyed_timers/README.md) — own replaceable OTP timers in a Plugin runtime.
3. [Bus Delivery](04_03_bus_delivery/README.md) — consume an ordered durable Bus subscription.
4. [Managed Jobs](04_04_managed_jobs/README.md) — run linked work after the request commit.
5. [Runtime Inspection](04_05_runtime_inspection/README.md) — read safe snapshots and runtime status.
6. [State Recovery](04_06_state_recovery/README.md) — restore state, revision, and input identity.
7. [Agent Observation](04_07_agent_observation/README.md) — collect semantic SDK events.
8. [Causal Trace](04_08_causal_trace/README.md) — follow one trace through parent and child work.
9. [Recoverable Delivery](04_09_recoverable_delivery/README.md) — resume committed external intent.
10. [Pending Job Recovery](04_10_pending_job_recovery/README.md) — make retry after runtime loss explicit.
11. [Durable Scheduling](04_11_durable_scheduling/README.md) — save and acknowledge schedule occurrences.

## Run the section

```sh
mix test test/examples/04_runtime --include example --seed 0
```

Expected result: the runtime behavior tests pass without network access or
credentials.

## Shared support

- [Event probe](support/event_probe.ex) collects semantic telemetry for two observation examples.
- [Job runtime](support/job_runtime.ex) supplies the managed work port and Plugin runtime used by two job examples.

## Limits

These examples use local processes and local persistence adapters. The
multi-node ownership and remote lifecycle contracts start in the next section.
