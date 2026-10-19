# Runtime examples

Use the paths below to find the runtime boundary that you need. Numbers stay
stable. Each lesson uses public Jido APIs and deterministic local services.

## Requests and control

1. [Request Modes](04_15_request_modes/README.md): call, cast, submit, await, overload, and admission deadlines.
2. [Turn Control](04_16_turn_control/README.md): inspect, cancel, quiesce, and resume.
3. [Failure Outcome](04_17_failure_outcome/README.md): errors before and after commit.

## Input and effects

1. [Scheduled Signals](04_01_scheduled_signals/README.md): later work through Scheduler Directives.
2. [Keyed Timers](04_02_keyed_timers/README.md): replaceable timers in a Plugin runtime.
3. [Bus Delivery](04_03_bus_delivery/README.md): an ordered durable Bus subscription.
4. [Managed Jobs](04_04_managed_jobs/README.md): linked work after commit.
5. [Heartbeat](04_18_heartbeat/README.md): a periodic input Plugin.

## Observation

1. [Runtime Inspection](04_05_runtime_inspection/README.md): safe snapshots and status.
2. [Agent Observation](04_07_agent_observation/README.md): semantic SDK events.
3. [Causal Trace](04_08_causal_trace/README.md): parent and child work in one trace.

## Changes and recovery

1. [Definition Changes and Diff](04_19_definition_changes/README.md): pure mutation and live route changes.
2. [Stable Reference](04_12_stable_reference/README.md): durable identity after runtime replacement.
3. [State Migration](04_14_state_migration/README.md): change schema, definition, and state together. Continue with [Definition Revision](../10_persistence/10_08_definition_revision/README.md).
4. [Pending Job Recovery](04_10_pending_job_recovery/README.md): explicit retry after runtime loss.
5. [Durable Scheduling](04_11_durable_scheduling/README.md): save and acknowledge occurrences.

## Run the section

```sh
mix test test/examples/04_runtime --include example --seed 0
```

Expected result: runtime tests pass without network access or credentials.

## Code layout and limits

The two job lessons keep their own ports and Plugin runtimes beside the Agent.
This local duplication keeps the important behavior visible. The small
[event probe](support/event_probe.ex) remains shared by observation lessons.

These examples use local processes and persistence adapters. Remote placement
and cluster ownership remain [research contracts](../99_research/README.md).
See [Persistence](../10_persistence/README.md) and
[Durable execution](../11_durable/README.md) for stored state and Flow recovery.
