---
modules:
  - Jido.AgentServer.DurableTurn
  - Jido.AgentServer.DurableTurn.CheckpointStore
  - Jido.AgentServer.DurableTurn.WaitHost
---

## Purpose

Protect persistent Flow progress inside one AgentServer Turn. This component
owns the saved Turn receipt, Runic workflow checkpoints, wait input receipts,
and recovery of that execution. It does not own Agent record formats, general
Agent commits, transient Turn execution, or post-commit effects.

The public boundary is `Jido.AgentServer.deliver_wait/4` together with the
existing AgentServer Turn, status, and cancellation APIs. The three
`Jido.AgentServer.DurableTurn` modules are internal. Flow and wait definition
belong to `jido_action`; this component adds no DSL.

## Obligations

### jido.agent_server.durable_turn.I1 — Saved Flow acceptance

- **scope:** persistent Flow Turn admission
- **must:** Before the first Action starts, validate Flow input and save one portable running receipt with the stable Turn ID, original and admitted Signals, prepared Plugin input, safe context, Flow definition fingerprint, and absolute expiry. Publish its Agent revision only after the required save. A rejected or uncertain acceptance save starts no Action and closes durable authority.
- **why:** Recovery needs a confirmed description of the accepted Flow before work starts.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I2 — Isolated execution checkpoint

- **scope:** durable workflow checkpoint storage
- **must:** Derive execution identity from instance namespace, partition, Agent ID, and Turn ID. Append each ordered Runic event batch once behind a conditional batch count. Store produced fact values and Join completion results under that execution identity. Use bounded fact-referenced frame deltas only when they are smaller than full values, and rebuild the exact value during recovery. Keep a fact manifest for collection. Recover a stored tail batch if its count update was interrupted. Reject corrupt records, isolate identities, and prevent cleanup by an old owner from removing a replacement owner's registration.
- **why:** Each durable Flow needs one fenced checkpoint authority.
- **kind:** persisted-format
- **status:** active

### jido.agent_server.durable_turn.I3 — Compatible recovery input

- **scope:** restore of a running durable Flow Turn
- **must:** Rebuild preparation from the saved Agent, Signals, safe context, Plugin input, Turn ID, and absolute expiry. Require the saved Flow fingerprint to match the loaded definition. Fail on missing, corrupt, or incompatible execution data and do not start a new Flow as a fallback.
- **why:** Recovery must continue the accepted execution, not create different work.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I4 — Confirmed graph progress

- **scope:** durable Flow node execution
- **must:** Validate portable Flow facts and confirm the current workflow checkpoint before dispatching the next node. Stop durable authority on rejection, conflict, invalid data, task loss, or uncertain write. Recovery can repeat unconfirmed work but must not repeat work before the last confirmed checkpoint.
- **why:** A downstream Action must never start from progress that storage did not confirm.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I5 — Execution recovery and ownership

- **scope:** AgentServer, activation, or Runic Worker replacement
- **must:** Resume the same execution identity and Turn after owned runtime loss. Rebuild or resume one owned Runic Worker from the confirmed checkpoint, keep the committed Agent unchanged until Flow completion, and clean the Worker before later Turn work. Do not reconstruct a lost caller reply.
- **why:** Runtime replacement must not create a second execution or a second commit.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I6 — Saved wait suspension

- **scope:** a durable Flow with open waits
- **must:** Save pending waits, their stable IDs, and their absolute deadline before suspending and releasing the Runic Worker. Keep the Turn active, committed reads available, and later Turns queued. Restore the same waits after hibernation or runtime loss without rerunning confirmed Actions.
- **why:** Waiting must consume no Worker while retaining exact durable progress.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I7 — Durable wait input

- **scope:** `Jido.AgentServer.deliver_wait/4`
- **must:** Accept a Signal only for an open wait of a suspended durable Flow. Require an exact portable input shape, matching wait and event, and no more than 1024 saved input receipts. Save acceptance before acknowledgement. Treat an equal Signal ID retry as inert and reject a conflicting reuse of that ID.
- **why:** A caller must be able to retry an uncertain wait delivery without duplicate input.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I8 — Wait resolution and time

- **scope:** saved wait input and timer resolution
- **must:** Save wait resolution before downstream work starts. Preserve accepted input across recovery when its acknowledgement or resolution save is lost. Order receipts by saved acceptance order even if the wall clock moves backward. Keep saved absolute wait deadlines and use bounded timer intervals without resetting them.
- **why:** External input and time must cross one durable resolution boundary.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I9 — Terminal Flow receipt and collection

- **scope:** durable Flow completion and failure
- **must:** Save completed, failed, or cancelled Turn status with the complete Agent revision before a terminal reply or later Turn starts. Commit a successful Flow once. Preserve Agent state on failure. Restore a confirmed completion without rerunning Actions, Plugin commit hooks, or returned Directives. Delete the separate execution checkpoint only after the terminal Agent revision is durable. A failed physical delete must not change the terminal Turn result.
- **why:** Terminal recovery must distinguish completed work from work that still needs execution.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I10 — Abort and expiry closure

- **scope:** cancellation and timeout of a durable Flow
- **must:** Stop owned startup or Worker work, confirm cleanup, and save a terminal receipt before opening later admission. Reject late wait input. Preserve the first abort result. On restore, apply the saved absolute Turn expiry and do not grant a new timeout budget.
- **why:** Aborted durable work must not continue or revive with more time.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable_turn.I11 — Durable capability and public boundary

- **scope:** durable and transient Flow execution; `Jido.AgentServer.deliver_wait/4`
- **must:** Keep wait delivery on the documented AgentServer facade with a typed, non-empty wait ID, a Signal, and a validated caller timeout. Keep durable-turn coordination modules internal and add no core DSL. Enable workflow recovery and waits only when persistence is configured. Reject waits on ordinary AgentServer execution before Actions start and reject caller attempts to supply internal durable-host context. Do not restore an interrupted transient Flow or save execution graphs for ordinary Action Turns.
- **why:** Durable behavior must be explicit and must not be created by input data.
- **kind:** functional
- **status:** active
