---
modules:
  - Jido.Durable
  - Jido.Durable.Operation
  - Jido.Durable.Ref
  - Jido.Durable.Status
---

## Purpose

Run and inspect a persisted Flow through its portable execution reference.
This contract covers the direct API. AgentServer owns admission for its Turns.

## Obligations

### jido.durable.I1 — Exclusive operation ownership

- **scope:** `Jido.Durable.start/4`, `resume/3`, and `signal/5`
- **must:** Admit one direct operation per reference at a time within a Jido
  instance. Return `{:error, :execution_busy}` to competing calls before changing
  the checkpoint or interrupting active work. Keep other references independent.
  Release admission when the owner exits so another caller can recover.
- **why:** Replacing a live operation can repeat an Action.
- **kind:** ordering
- **status:** active

### jido.durable.I2 — Operation deadline

- **scope:** the direct operation timeout and worker lifecycle
- **must:** Use one monotonic budget across progress notifications. Stop owned
  work before returning a retryable timeout. Resume from the last confirmed
  checkpoint, and make stale progress notifications inert.
- **why:** Callers must be able to retry without leaving an abandoned worker.
- **kind:** ordering
- **status:** active

### jido.durable.I3 — Ready work with open waits

- **scope:** `Jido.Durable.status/2`
- **must:** Report inactive runnable work as `:ready` even when the checkpoint
  has an open wait. Keep pending waits and their next wake time available.
- **why:** A host can resume ready work before the next timer expires.
- **kind:** functional
- **status:** active

### jido.durable.I4 — Read-only checkpoint projections

- **scope:** `Jido.Durable.status/2` and `result/2`
- **must:** Read the last confirmed checkpoint without changing continuation
  registration or checkpoint records. Preserve missing-reference errors,
  live status, and the stored execution result.
- **why:** A caller can inspect a live execution without taking its storage
  authority.
- **kind:** functional
- **status:** active
