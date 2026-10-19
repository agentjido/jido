# 11_15 Execution Rollover

**Status: proposed; README only.** No source or example test exists.

Finish one Turn and atomically accept a successor Turn with a fresh Flow graph.
One Flow execution is one Turn. A chain links the related Turns.

## Current contract and gap

Current Dispatch selects another executable inside the same graph. It does not
commit an Agent or start a new Turn. There is no core rollover API. Keep ordinary
`{:continue, input, target}` behavior unchanged; new syntax remains undecided.
See [jido_action #303](https://github.com/agentjido/jido_action/issues/303).

| Property | Current Dispatch | Proposed rollover |
| --- | --- | --- |
| Next work | Expand the same graph | Start a fresh Flow in a new Turn |
| Identity | Same execution | Same Agent and chain; new Turn ID |
| Agent state | Commit at final Turn completion | Commit at each handoff |
| Effects | Accumulate until final success | Belong to the Turn that produced them |
| Timeout | Same Turn budget | New Turn budget; optional absolute chain deadline |
| Caller | One execution result | One chain result plus individual Turn receipts |

Temporal closes one run and starts another with the same Workflow ID, a new
Run ID, fresh history, and explicit input. See
[Temporal continue-as-new](https://docs.temporal.io/develop/typescript/workflows/continue-as-new)
and the current [Dispatch contract](https://github.com/agentjido/jido_action/blob/release/v3/guides/dynamic-flows.md).

## Atomic handoff

```text
Turn A produces candidate Agent state + successor target/input
validate state, effects, target, and input
save together: Agent state + A completion + B acceptance + chain link/order
finish A's normal post-commit effect phase
run queued work in admission order, including B
```

Give B a stable Turn ID before saving. A lost save reply must be resolved before
another successor is accepted. Recovery sees either pending A or committed A
with accepted B, never committed A without B or two successors. Do not send a
self-Signal after commit to create B: that leaves a loss window.

Carry explicit input and start a fresh graph. B reads the then-current committed
Agent state when it starts; earlier queued commands may have changed that state.
Do not carry A's candidate as a replacement for newer state. A committed state
change remains committed if B fails. Effects follow the existing post-commit
rules before the next Turn; handoff adds no effect replay or exactly-once I/O.

## Queue order

- Assign B a queue position at the handoff's serialized acceptance point.
- Commands already admitted go before B. Commands admitted later go after B.
- Each successor joins the tail. A chain cannot repeatedly take the next slot.
- Save B's identity and order with the handoff; recovery must not enqueue it twice.
- Ordinary queued Signals are currently not durable. This proposal guarantees
  recovery of the accepted successor, not survival of those ordinary Signals.
  Preserve order among retained work; do not claim a durable general inbox.

## Caller completion

A's Turn receipt reports committed continuation and identifies B and the chain.
It is not final chain success. The original logical request completes only when
a Turn ends without a successor, fails, or is cancelled. Intermediate outputs
are available through Turn receipts; the final Turn supplies the chain result.
A caller timeout or disconnect does not cancel the chain. Stable chain/result
lookup is required for reconnection; see [11_17](../11_17_turn_receipts/README.md).
These are proposed receipt semantics, not existing reply APIs.

## Cancellation and deadlines

Use a stable chain ID to cancel the remaining chain. Save cancellation before
stopping the active member or removing its accepted, queued successor. Serialize
cancellation with handoff: cancellation first prevents B; handoff first makes B
the cancellation target. Prevent all later successors. Repeat cancellation safely.

Cancelling an active or queued member Turn terminates that chain as cancelled.
A completed member cannot be cancelled or undone; use chain cancellation to
stop its successor. Earlier commits and external I/O remain. Cancellation does
not affect unrelated queued work or undo committed effects.

Each Turn gets a new Turn timeout. If an absolute chain deadline is configured,
carry it unchanged and check it before successor execution. Never reset it at a
handoff. In this proposal queue time counts toward that deadline; expiry ends
the chain without running the queued successor. It does not undo earlier Turns.

Inputs address a specific Turn and wait occurrence. Do not automatically transfer
A's pending input or callbacks to B. Reject stale targets; send new input to B
explicitly. A future chain-addressed input contract needs separate review.

## Planned proof

- Crash before handoff save, after save, and after a lost storage reply. Prove
  one successor, one committed state transition, and no repeated completed work.
- Queue an unrelated command before and after handoff. Prove the declared order
  and that B reads current state after the earlier command.
- Keep the caller pending through A; return B's final result or terminal failure.
  Recover and look up the same chain result after caller loss.
- Cancel before handoff, while B is queued, and while B runs. Recover the saved
  cancellation without running another successor or undoing earlier state.
- Prove new Turn budgets, a preserved chain deadline, and rejection of stale input.
- Repeat handoffs with bounded active graph data and bounded chain metadata.
  Retention must preserve pending links, receipts, and duplicate detection needs.

## Reading and execution

Read the [section contract](../../README.md) and
[Flow control proposal](../flow-control/README.md). There is no run command
or executable evidence yet. Add source and tests after contract review.
Use memory or ETS, controlled clocks, and explicit test barriers. Do not claim
recovery after loss of the retained store. No runtime implementation is included.

## Integration gate

Requires a verified explicit handoff result and stable receipt lookup from
11_17. Coordinate it in the existing AgentServer `gen_statem`, with pure chain
transitions over bounded saved data. Add no new process or custom directive
drain loop. OTP events do not replace saved acceptance or queue-order metadata.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_14](../11_14_recovery_compatibility/README.md) | Next: [11_16](../11_16_retry_recovery/README.md)
