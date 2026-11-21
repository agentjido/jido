---
title: Jido.AgentServer component
status: current
last-reviewed: 2026-11-19
---

# Jido.AgentServer component

Purpose: Host one resident Agent activation and run every accepted Signal
through one serialized Turn path.

Review result: The component boundary and public facade are confirmed. The
Jido Instance owns logical Agent life, stable Address routing, persistence choice,
activation, passivation, durable wake records, reconciliation, deletion, and
definition upgrade. AgentServer owns only the current resident activation.

## Public contract

The facade has 14 functions:

- `child_spec/1`
- `call/3`, `cast/3`, `submit/3`, `await/2`, and `abandon/1`
- `cancel_turn/3`
- `quiesce/2`, `resume/2`, and `stop/3`
- `remove_topology_member/4`
- `snapshot/2`, `status/2`, and `await_ready/2`

The public values are `Pending`, `TurnResult`, `Snapshot`, and `Status`.
`Jido.Agent.Address` is the normal logical address. An AgentServer PID or OTP name
addresses only one current activation.

All request modes use one Turn path. Accepted terminal states are data in a
`TurnResult`. `{:error, reason}` means that work was not accepted or the
transport failed. Cast runs the same Turn and commit path but discards its
reply.

An asynchronous stable-Address submission can supply a `turn_id` and set
`result_handoff: true`. This lets product data record the exact Turn before it
submits work. The durable record then retains one exact terminal `TurnResult`. Use
`Jido.turn_result/3` to read it without a process handle and
`Jido.acknowledge_turn_result/3` to clear it. The Agent rejects later Turns
until acknowledgement. Records written before this optional field remain
valid.

`remove_topology_member/4` removes one declared member slot from the current
root activation. It closes admission for the selected subtree, settles
accepted work, and stops descendants before their parent. It keeps the root,
the static definition, and durable child records. A partial failure keeps the
removal pending for a safe retry. A replacement root activation creates the
declared slot again.

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
Terminal result acknowledgement is one such operation.

## Proof

The focused contract suite covers stable Address delivery, warm residency,
passivation, worker recovery, accepted failure values, durable Signal retry,
exact result handoff across Instance restart, timer wake-up after Instance
restart, concurrent activation, uncertain-write reconciliation, definition
upgrade, stable Plugin runtime, and controlled declared-subtree removal.

## Standalone V3 review

Reviewed on 2026-11-19 at [`6fdc009a1edd6261f3e26509fa2905bb9192faa5`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5).
The review covers the four checks in [components.md](../../components.md).
Each finding links to the [V3 review queue](https://github.com/agentjido/jido/issues/453).

### Public surface

The public facade exports the 14 documented functions and the `server()` type.
`child_spec/1` supplies a supervisor child specification. The Instance provides
logical Agent operations by Address. A worker PID or registered OTP name
provides a handle for the resident activation.

- `call/3` accepts a wait timeout or options for `:timeout`,
  `:admission_timeout`, and `:context`. `submit/3` accepts admission and
  context options, a caller-supplied `:turn_id`, and `:result_handoff` for
  durable Agents. `cast/3` accepts `:context` and uses best-effort delivery.
- `await/2` can time out and let the submitting process try again.
  `abandon/1` discards reply tracking while the Turn can continue. A
  synchronous OTP wait can exit on timeout or process loss. The caller wait,
  admission budget, and active Turn deadline run independently.
- Accepted work returns a `TurnResult` with the activation ID, Turn ID,
  outcome, and revisions. The result can report `:waiting` before terminal
  completion. Normal return values also cover failed, cancelled, timed out,
  and uncertain Turns. Rejection and transport failure have error paths.
- `status/2` reports semantic runtime state. `snapshot/2` reads the committed
  Agent and revisions in one worker event. `await_ready/2` checks startup.
  `quiesce/2` takes a finite budget and an active work policy of `:finish`
  or `:cancel`. `resume/2` reopens admission after work settles.
  `cancel_turn/3` matches active work and its Handoff chain. A distinct
  postponed Turn cannot be cancelled by ID. `stop/3` returns a snapshot
  after resident shutdown. `remove_topology_member/4` delegates to the
  composition component.

[facade](../../lib/jido/agent_server.ex),
[request validation and transport](../../lib/jido/agent_server/worker.ex#L466-L667),
and [exact public API test](../../test/jido/agent_server/core/api_test.exs#L64-L94).

### API contract usage

`Jido.call/4`, `Jido.cast/3`, `Jido.submit/4`, and `Jido.cancel_turn/4`
resolve an Address and call the resident facade. Result lookup and acknowledgement
use the Instance. The launch and request examples call the same facade by
worker PID. Timer and managed job producers call `cast/3` without waiting for
a result. Instance ownership calls the internal worker protocol after it
serializes transfer and checks the ancestry.

The current tests cover each request mode, FIFO replay, capacity per request
when Turn IDs match, caller timeout, repeatable await, abandonment, and active
cancellation. They also cover accepted failure, commit before effects, one
activation under concurrent Address delivery, worker replacement, uncertain
write reconciliation, and fenced ownership transfer. The API test verifies
the exported surface. The guide findings concern what the public docs tell
callers about that surface.

[Address callers](../../lib/jido.ex#L703-L720),
[request examples](../../examples/06_agent_server/06_03_request_modes/request_modes_test.exs),
[Turn controls](../../examples/06_agent_server/06_06_turn_control/turn_control_test.exs),
[ownership tests](../../test/jido/instance/ownership_transfer_test.exs), and
[activation tests](../../test/jido/agent_server/durable_activation_contract_test.exs).

### Code quality

The worker tracks each postponed request in both a set and a map. One entry
per request can hold its caller and gate. The queue must keep its current
capacity, order, early quiesce reply, and later OTP drain. The public status
path can drop the unused mailbox length and the write-only historical effect
outcome. Keep the public values, active effect tracking, telemetry, and
topology failure logs. The current state machine already shares the normal
Turn path across all request modes.

[queue accounting](../../lib/jido/agent_server/worker.ex#L3183-L3209),
[queue drain](../../lib/jido/agent_server/worker.ex#L3985-L4019),
[status projection](../../lib/jido/agent_server/status.ex#L74-L93), and
[effect reporting](../../lib/jido/agent_server/worker.ex#L3611-L3646).

### Elixir and OTP design

Keep the worker as the only owner of the resident Turn state machine.
Lifecycle tasks run outside its event loop. The worker publishes execution
ownership before starting execution, then confirms cleanup before publishing
a commit. A committed Turn can have effects pending after its result. The
activation root owns its ETS checkpoint and the Plugin supervisor. The
transient, significant worker restarts on abnormal exit. A clean shutdown
ends the activation. This keeps the activation identity and healthy Plugins
through worker replacement. The Instance owns stable Address routing and
reconciliation. A dynamic owner relation monitors the owner activation
and persists in the child root's ETS until the child activation ends.

A stop needs one worker-owned transition from closed admission through final
snapshot and shutdown. A faulted worker needs a cancellation response that
keeps the reconciliation boundary and worker identity. The activation,
effects, Plugin runtime, composition, durable state, durable Turn, and
Handoff mechanics were checked at their interfaces. Their separate reviews
remain open.

[activation supervisor](../../lib/jido/agent_server/supervisor.ex#L33-L71),
[execution ownership and cleanup](../../lib/jido/agent_server/worker.ex#L2865-L2908),
[accepted ownership](../../lib/jido/agent_server/worker.ex#L912-L987), and
[Instance transfer](../../lib/jido/instance/ownership.ex#L10-L65).

### Review findings

| Issue | Severity | Evidence and acceptance check |
| --- | --- | --- |
| [#476](https://github.com/agentjido/jido/issues/476) | P1 | Concurrent resume let revision 1 commit after stop captured revision 0. Keep admission closed through the final snapshot and activation exit. |
| [#477](https://github.com/agentjido/jido/issues/477) | P2 | Cancellation reached the generic event clause with `active: nil` in the faulted phase. Return a reconciliation error and keep the faulted worker available for inspection. |
| [#478](https://github.com/agentjido/jido/issues/478) | P2 | The reply gate stayed alive after quiesce rejected a queued request and after a submission to an absent name failed. Close the gate in both paths and preserve request ownership and queue rules. |
| [#479](https://github.com/agentjido/jido/issues/479) | P2 | A distinct queued ID returned `:stale_turn` and that Turn committed after the active Turn. Update the API reference and guide examples to match the facade and current result shapes. |
| [#480](https://github.com/agentjido/jido/issues/480) | P3 | The status projection discards the mailbox length and never reads the historical effect outcome. Remove those internal operations and preserve public inspection and telemetry. |

The issue bodies give pinned code references and acceptance checks. Prior
[#372](https://github.com/agentjido/jido/issues/372) and
[#422](https://github.com/agentjido/jido/issues/422) cover earlier code
cleanup, queue capacity, and recovery changes.

### Verification

- 104 existing AgentServer, ownership, and numbered example tests passed.
- Five local probes reproduced the stop race, faulted cancellation crash,
  quiesce reply gate leak, absent-name reply gate leak, and queued cancellation
  behavior. The fault probe also checked worker replacement and reconciliation.
- `mix format --check-formatted` passed. The checks ran with Elixir 1.20.4
  and OTP 29 using a separate build directory.

### Implementation

- The Worker owns the stop drain and final snapshot. The caller waits for the
  same activation root to exit before it returns the snapshot.
- A faulted Worker returns `{:error, :reconciliation_required}` for
  cancellation. Queued request rejection and transport failure release reply
  gates.
- The public reference and guides describe the facade and its current result
  values. The status projection no longer reads the mailbox length, and the
  Worker keeps only the active Turn's effect outcome.
- The regression tests cover stop admission, a registered name that changes,
  faulted cancellation, and reply gate cleanup after rejection or delivery
  failure. AgentServer obligations I101, I106, and I107 record the guarantees.

## Sources

- [Facade](../../lib/jido/agent_server.ex)
- [Worker](../../lib/jido/agent_server/worker.ex)
- [Status](../../lib/jido/agent_server/status.ex)
- [Durable activation contract](../../test/jido/agent_server/durable_activation_contract_test.exs)
- [AgentServer obligations](../../test/contracts/jido/agent_server.obligations.md)
- [Declared-subtree removal decision](../adr/0005-activation-local-declared-subtree-removal.md)
- [Architecture plan](../architecture/durable-agent-activation.md)
