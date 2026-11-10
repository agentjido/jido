# 08 Runtime

Use the paths below to find the runtime boundary that you need. Numbers stay
stable. Each lesson uses public Jido APIs and deterministic local services.

## Requests and control

1. [Request Modes](08_01_request_modes/README.md): call, cast, submit, await, overload, and admission deadlines.
2. [Turn Control](08_02_turn_control/README.md): inspect, cancel, quiesce, and resume.
3. [Failure Outcome](08_03_failure_outcome/README.md): errors before and after commit.

## Input and effects

1. [Scheduled Signals](08_04_scheduled_signals/README.md): later work through Scheduler Directives.
2. [Keyed Timers](08_05_keyed_timers/README.md): replaceable timers in a Plugin runtime.
3. [Bus Delivery](08_06_bus_delivery/README.md): an ordered durable Bus subscription.
4. [Managed Jobs](08_07_managed_jobs/README.md): linked work after commit.
5. [Heartbeat](08_08_heartbeat/README.md): a periodic input Plugin.

## Observation

1. [Runtime Inspection](08_09_runtime_inspection/README.md): safe snapshots and status.
2. [Agent Observation](08_10_agent_observation/README.md): semantic SDK events.
3. [Causal Trace](08_11_causal_trace/README.md): parent and child work in one trace.

## Changes and recovery

1. [Definition Changes and Diff](08_12_definition_changes/README.md): pure mutation and live route changes.
2. [Stable Reference](08_13_stable_reference/README.md): durable identity after runtime replacement.
3. [State Migration](08_14_state_migration/README.md): change schema, definition, and state together. Continue with [Definition Revision](../13_persistence/13_08_definition_revision/README.md).
4. [Pending Job Recovery](08_15_pending_job_recovery/README.md): explicit retry after runtime loss.

## Run the section

```sh
mix test test/examples/08_runtime --include example --seed 0
```

Expected result: runtime tests pass without network access or credentials.

## Code layout and limits

The two job lessons keep their own ports and Plugin runtimes beside the Agent.
This local duplication keeps the important behavior visible. The small
[event probe](support/event_probe.ex) remains shared by observation lessons.

These examples use local processes and persistence adapters. Remote placement
and cluster ownership are outside this supported example suite.
See [Persistence](../13_persistence/README.md) and
[Durable execution](../14_durable_agents/README.md) for stored state and Flow recovery.
