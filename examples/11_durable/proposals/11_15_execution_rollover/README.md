# 11_15 Execution Rollover

**Status: implemented in core; this proposal folder has no runnable example.**

Finish one Turn and atomically accept a successor Turn with a fresh executable.
A chain links the related Turns.

## Current contract

Invoke selects another executable inside the same graph. It does not commit an
Agent or start a new Turn. Terminal Handoff returns
`{:handoff, instruction, effects}` from Exec. Direct `Jido.Agent.cmd/3` returns
`{:handoff, candidate, instruction, directives}` without running the
successor. AgentServer runs the successor as a new Turn.

| Property | Invoke | Handoff |
| --- | --- | --- |
| Next work | Expand the same graph | Start a fresh Action or Flow in a new Turn |
| Identity | Same execution | Same Agent and chain; new Turn ID |
| Agent state | Commit at final Turn completion | Commit at each handoff |
| Effects | Accumulate until final success | Belong to the Turn that produced them |
| Timeout | Same Turn budget | New Turn budget after predecessor effects |
| Caller | One execution result | One final chain result; durable receipt lookup is not public |

Temporal closes one run and starts another with the same Workflow ID, a new
Run ID, fresh history, and explicit input. See
[Temporal continue-as-new](https://docs.temporal.io/develop/typescript/workflows/continue-as-new)
and the current [Flow contract](https://github.com/agentjido/jido_action/blob/release/v3/guides/dynamic-flows.md).

## Atomic handoff

```text
Turn A produces candidate Agent state + successor target/input
validate state, effects, target, and input
save together: Agent state + B acceptance + chain link/order
finish A's normal post-commit effect phase
save B release after live Plugin preparation and admission
start B before postponed Turn work
```

Give B a stable Turn ID before saving. A lost save reply must be resolved before
another successor is accepted. Recovery sees either pending A or committed A
with accepted B, never committed A without B or two successors. Do not send a
self-Signal after commit to create B: that leaves a loss window.

Carry explicit input and start a fresh graph. B reads A's committed Agent state.
A committed state change remains committed if B fails. Effects follow the
existing post-commit rules before the next Turn. Handoff adds no effect replay
or exactly-once I/O.

## Queue order

- Assign B a stable identity at the Handoff acceptance point.
- Keep all postponed Turn requests behind B.
- Start B from the AgentServer mailbox tail after the explicit
  `:handoff_pending` state.
- Save B's identity and order with the handoff; recovery must not enqueue it twice.
- Ordinary queued Signals are currently not durable. This proposal guarantees
  recovery of the accepted successor, not survival of those ordinary Signals.
  Preserve order among retained work; do not claim a durable general inbox.

## Caller completion

A's durable receipt identifies B and the chain. It is not final chain success.
The original logical request completes only when a Turn ends without a
successor, fails, or is cancelled. The final Turn supplies the reply. A caller
timeout or disconnect does not cancel the chain. Stable chain and result lookup
remains proposed; see [11_17](../11_17_turn_receipts/README.md).

## Cancellation and deadlines

Cancel the active chain member with `:active`, its predecessor Turn ID, or its
successor Turn ID. Save cancellation before successor start. Cancellation first
prevents B; Handoff first makes B the cancellation target.

Cancelling an active or queued member Turn terminates that chain as cancelled.
A completed member cannot be cancelled or undone. Earlier commits and external
I/O remain. Cancellation does not affect unrelated queued work or undo
committed effects.

Each Turn gets a new Turn timeout after predecessor effects finish. An absolute
chain deadline is not implemented.

Inputs address a specific Turn and wait occurrence. Do not automatically transfer
A's pending input or callbacks to B. Reject stale targets; send new input to B
explicitly. A future chain-addressed input contract needs separate review.

## Proof status

- [x] Recover an accepted intent as failed without repeated effects.
- [x] Recover one released Action or Flow successor with the same Turn ID.
- [x] Keep postponed work behind the successor and use its committed state.
- [x] Keep the caller pending through the chain and return the final result or
      failure.
- [x] Cancel during predecessor effects, release persistence, and successor
      execution.
- [x] Give the successor a new Turn budget after predecessor effects.
- [x] Repeat Handoffs with one chain ID and increasing chain order.
- [ ] Add stable chain-result lookup after caller loss.
- [ ] Add an absolute chain deadline and a public chain cancellation API.

## Reading and execution

Read the [section contract](../../README.md) and
[Flow control proposal](../flow-control/README.md). This folder has no run
command. Core evidence is in the durable Handoff Covenant tests. They use local
storage and explicit test barriers. They do not claim recovery after loss of
the retained store.

## Remaining work

Stable receipt lookup from 11_17, an absolute chain deadline, and a public
chain cancellation API remain proposals. Follow the
[integration checklist](../flow-control/INTEGRATION.md).

Previous: [11_14](../11_14_recovery_compatibility/README.md) | Next: [11_16](../11_16_retry_recovery/README.md)
