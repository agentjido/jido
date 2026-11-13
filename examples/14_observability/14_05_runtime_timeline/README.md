# 14_05 Runtime Timeline

Public `AgentServer.Status` values show one Turn move from idle to waiting to
committed.

## What you will learn

- How to separate operational status from committed Agent state.
- How `active_turn_id`, waits, revision, and last outcome change over time.
- How to build an application-owned process-neutral status projection.

## Read the code

Read [the waiting Agent, Flow, and projection](runtime_timeline.ex), then the
three observation points in the test.

## Run it

`mix test.examples examples/14_observability/14_05_runtime_timeline --warnings-as-errors`

Expected result: one Turn keeps its ID while it waits, then commits revision
one and returns to idle.

## Important behavior

`AgentServer.Status` is operational data. `AgentServer.Snapshot` contains the
complete committed Agent. A browser or external caller should receive an
application-owned projection, not the complete snapshot.

## Limits

The three points are sampled after synchronized calls. They are not a durable
event history and do not capture every internal transition.

## Core Fit and Gaps

The public status value provides the stable fields needed for an operational
timeline. A durable history, retention policy, and user-facing projection
remain application or observability-system work.

## Files

- [Source](runtime_timeline.ex)
- [Tests](runtime_timeline_test.exs)

Previous: [OpenTelemetry](../14_04_open_telemetry/README.md) |
Next: [Failed Turn Debugging](../14_06_failed_turn_debugging/README.md)
