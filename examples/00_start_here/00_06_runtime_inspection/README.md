# 00_06 Runtime inspection

Wait for an expense decision, commit the result, run a notification effect,
and inspect one later failure.

## What you will learn

- How `TurnResult`, `Status`, and `Snapshot` show different runtime facts.
- How an Agent wait resumes from a normal Signal.
- How a Plugin effect runs after commit and stops with its Agent.

## Read the code

Read [the Agent and approval Flow](runtime_inspection.ex), then read the
[notification capability](notification.ex) and behavior test.

## Run it

```sh
mix test.examples examples/00_start_here/00_06_runtime_inspection --warnings-as-errors
```

Expected result: the Agent waits, approves the expense, records one
post-commit notification, preserves the approved state after a failed Turn,
and cleans up its notification runtime.

## Important behavior

The waiting Turn has one stable Turn ID. The approval Signal resumes that Turn.
The Jido instance uses a stable namespace and a local ETS persistence adapter
because AgentServer waits require a durable execution host. AgentServer
commits the approved state before it dispatches the notification. The later
validation failure does not change committed state.

## Limits

The ETS record can restore an Agent process in the same BEAM. It does not
survive BEAM loss. The notification has no retry or idempotency contract.

## Core Fit and Gaps

- Logical owner: the expense Agent.
- Process owner: the Jido activation supervisor.
- Canonical state owner: the expense Agent state.
- Commit point: the approved candidate commit before notification dispatch.
- Persisted data: the Agent record, open wait, and Flow progress in local ETS.
- Retry boundary: none in this lesson.
- Idempotency rule: none for notifications.
- Injected failure: invalid data in a later accepted Turn.
- Recovery result: the approved committed state stays unchanged.
- Non-guarantees: no durable wait, effect replay, or exactly-once delivery.

The public wait, status, snapshot, persistence, Plugin, and effect contracts
compose without a private runtime API.

The first implementation used an in-memory AgentServer and returned
`unsupported_host` for the wait capability. Adding persistence then required a
stable namespace. Configuring both public contracts fixes the behavior. This
is a documentation and learning-order friction point: the first-hour path
needs namespace and persistence concepts before their later chapters. It is
not a missing SDK operation.

## Files

- [Agent and Flow](runtime_inspection.ex)
- [Notification capability](notification.ex)
- [Tests](runtime_inspection_test.exs)

Previous: [Hosted Agent](../00_05_hosted_agent/README.md)
