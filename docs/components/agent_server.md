---
title: Jido.AgentServer component
status: current
last-reviewed: 2026-11-12
---

# Jido.AgentServer component

Purpose: Host one resident Agent activation and run every accepted Signal
through one serialized Turn path.

Review result: The component boundary and public facade are confirmed. The
Jido Instance owns logical Agent life, stable Address routing, persistence choice,
activation, passivation, durable wake records, reconciliation, deletion, and
definition upgrade. AgentServer owns only the current resident activation.

## Public contract

The facade has 13 functions:

- `child_spec/1`
- `call/3`, `cast/3`, `submit/3`, `await/2`, and `abandon/1`
- `cancel_turn/3`
- `quiesce/2`, `resume/2`, and `stop/3`
- `snapshot/2`, `status/2`, and `await_ready/2`

The public values are `Pending`, `TurnResult`, `Snapshot`, and `Status`.
`Jido.Agent.Address` is the normal logical address. An AgentServer PID or OTP name
addresses only one current activation.

All request modes use one Turn path. Accepted terminal states are data in a
`TurnResult`. `{:error, reason}` means that work was not accepted or the
transport failed. Cast runs the same Turn and commit path but discards its
reply.

## OTP boundary

One activation root owns the AgentServer worker and Plugin supervisor. A
worker restart keeps the activation ID and healthy Plugin runtime. Passivation
stops the activation. Reactivation creates a new activation ID but keeps the
stable Agent Address.

The worker, activation supervisor, Plugin roots, execution workers, internal
state-machine phases, effect detail, and composition records are not public
inspection data.

`Jido.transfer_agent_ownership/4` adds one local owner monitor to a resident
child activation. The Instance owns Address validation, transfer serialization,
and cycle checks. AgentServer keeps the accepted relation across worker
replacement. The relation ends with the child activation and is not durable.

## Durable boundary

AgentServer can host a durable Flow Turn, but it does not own durable workflow
authoring. `Jido.Durable` accepts only `Jido.Flow` and reuses `Jido.Exec`.
Signals resume saved waits through the stable Address delivery path. The Instance
stores wake deadlines so a timer can reactivate a passivated Agent after a
restart.

Agent revision and persistence revision are separate public fields. A durable
operation can change the persistence revision without changing Agent state.

## Proof

The focused contract suite covers stable Address delivery, warm residency,
passivation, worker recovery, accepted failure values, durable Signal retry,
timer wake-up after Instance restart, concurrent activation, uncertain-write
reconciliation, definition upgrade, and stable Plugin runtime.

## Sources

- [Facade](../../lib/jido/agent_server.ex)
- [Worker](../../lib/jido/agent_server/worker.ex)
- [Status](../../lib/jido/agent_server/status.ex)
- [Durable activation contract](../../test/jido/agent_server/durable_activation_contract_test.exs)
- [AgentServer obligations](../../test/contracts/jido/agent_server.obligations.md)
- [Architecture plan](../architecture/durable-agent-activation.md)
