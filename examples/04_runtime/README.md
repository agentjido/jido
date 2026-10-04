# Runtime examples

These examples move from short-lived runtime work to observation and durable
scheduling. Each example uses deterministic local services and
public Jido APIs.

## Learning order

1. [Scheduled Signals](04_01_scheduled_signals/README.md) — emit later work with Scheduler Directives.
2. [Keyed Timers](04_02_keyed_timers/README.md) — own replaceable OTP timers in a Plugin runtime.
3. [Bus Delivery](04_03_bus_delivery/README.md) — consume an ordered durable Bus subscription.
4. [Managed Jobs](04_04_managed_jobs/README.md) — run linked work after the request commit.
5. [Runtime Inspection](04_05_runtime_inspection/README.md) — read safe snapshots and runtime status.
6. [Agent Observation](04_07_agent_observation/README.md) — collect semantic SDK events.
7. [Causal Trace](04_08_causal_trace/README.md) — follow one trace through parent and child work.
8. [Pending Job Recovery](04_10_pending_job_recovery/README.md) — make retry after runtime loss explicit.
9. [Durable Scheduling](04_11_durable_scheduling/README.md) — save and acknowledge schedule occurrences.
10. [Stable Reference](04_12_stable_reference/README.md) — resolve durable identity after process and instance replacement.
11. [Turn Upgrade](04_13_turn_upgrade/README.md) — serialize release installation at the public idle boundary.
12. [State Migration](04_14_state_migration/README.md) — migrate domain and Plugin state as one validated commit.
13. [Request Modes](04_15_request_modes/README.md) — compare synchronous, best-effort, and asynchronous requests.
14. [Turn Control](04_16_turn_control/README.md) — inspect and cancel one matching active Turn.
15. [Failure Outcome](04_17_failure_outcome/README.md) — handle errors across the commit boundary.

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
Agent checkpoint and recovery behavior is in the
[persistence section](../10_persistence/README.md).
