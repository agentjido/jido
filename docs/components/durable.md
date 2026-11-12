---
title: Jido.Durable component
status: current
last-reviewed: 2026-11-11
---

# Jido.Durable component

Purpose: Run one persisted Flow from Signal input without requiring an Agent or
AgentServer.

Review result: All four checks have evidence (R9). The component and its public
shape are confirmed. Durable is separate from Agent state and AgentServer
lifecycle, but it uses the persistence and Runner services of a named Jido
instance.

## Public contract

| Surface | Contract |
| --- | --- |
| `Jido.Durable.ref/2` | Build one portable execution reference in a Jido instance namespace. |
| `Jido.Durable.start/4` | Start or idempotently resume one Flow from its initial Signal. Reject an Action target. |
| `Jido.Durable.resume/3` | Resume stored work until completion, failure, uncertainty, or the next wait. |
| `Jido.Durable.signal/5` | Save one Signal for an addressed wait and continue the same Flow. Equal Signal retries are inert. |
| `Jido.Durable.status/2` | Read portable state, waits, next wake time, and active status. |
| `Jido.Durable.result/2` | Read the normal Exec result from the last committed workflow state. |
| `Jido.Durable.Ref` | Identify one execution without a PID or storage adapter. |
| `Jido.Durable.Status` | Report the last committed durable execution state. |

The executable target must be `Jido.Flow`. Durable input must be `Jido.Signal`.
Caller context and stored values must be portable. The named Jido instance owns
the persistence adapter; no operation can replace it.

## API use and proof

Direct API tests cover completion, Action rejection, Signal wait resumption,
idempotent retry, conflicting Signal IDs, timer resumption, persistence
ownership, portable context, definition and input identity, option validation,
and invalid references. AgentServer reuses the internal Durable runtime for
durable Turns and adds Agent state commit, admission, effects, cancellation,
and supervision.

The examples cover persisted execution, waits, process recovery, and Agent
hosting. Persistence continuation tests cover saved facts, event batches,
conditional progress, recovery, and cleanup.

## Duplication and Elixir design

Durable reuses Exec compilation and Runic checkpoint state. It does not define
another workflow language or execution result. It uses `Jido.Exec.Wait` for
wait identity and matching, `Jido.Signal` for all durable input, and the Jido
instance persistence configuration for storage.

Keep Execution, Runtime, Ref, and Status as separate internal or value owners.
Execution is the stored command record. Runtime coordinates Runic. Ref is
portable identity. Status is the public read model. None justifies a separate
top-level component.

There is no public Journal. Runic history and persistence records already hold
the required execution evidence. There is no scheduler or cron engine. A host
uses `next_wake_at` or calculates a cron occurrence, then calls `resume/3` or
delivers a Signal.

## Findings and limits

- The direct Durable suite has one focused API file; broader recovery proof is
  shared with Persistence and AgentServer tests.
- Local tests do not prove every external store under node loss or uncertain
  network delivery.
- Work inside an unfinished compound component can repeat after recovery.
  Component boundaries, not arbitrary Action side effects, are checkpoint
  boundaries.
- AgentServer integration does not make Durable depend on AgentServer.

## Checks

The integrated R10 checkpoint passed warning-free compilation, formatting,
3,192 package tests with 111 normal exclusions, 246 examples, and all 321
active Covenant obligations.

## Sources

- [Public facade](../../lib/jido/durable.ex)
- [Execution record](../../lib/jido/durable/execution.ex)
- [Reference](../../lib/jido/durable/ref.ex)
- [Runtime](../../lib/jido/durable/runtime.ex)
- [Status](../../lib/jido/durable/status.ex)
- [Direct API tests](../../test/jido/durable/api_test.exs)
- [Durable AgentServer tests](../../test/jido/agent_server/durable)
- [Persistence continuation store](../../lib/jido/persistence/continuation_store.ex)

