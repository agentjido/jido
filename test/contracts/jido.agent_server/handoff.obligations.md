---
modules:
  - Jido.AgentServer
---

## Purpose

Protect one live Handoff chain in `Jido.AgentServer`. This component owns the
shared coordinator states and ordering that connect a terminal Flow Handoff to
its successor Turn. It also owns the accepted and released Handoff receipts
that make this chain recoverable.

Pure Agent evaluation belongs to `jido.agent_evaluation`. General durable Flow
progress belongs to `jido.agent_server.durable_turn`. Agent record validation
belongs to `jido.persistence`. This component adds no public DSL or public
module. It uses the existing `Jido.AgentServer` request, status, and
cancellation facade.

## Obligations

### jido.agent_server.handoff.I1 — Live Handoff chain

- **scope:** `Jido.AgentServer`, `Jido.Agent.Runner`
- **must:** Treat a terminal Flow Handoff as one predecessor commit followed by one successor Turn with a new Turn ID and a fresh timeout. Run predecessor Plugin hooks and Directives before successor Plugin preparation and admission. While the successor is pending, report `handoff_pending`, keep later work postponed, and start the successor from the AgentServer mailbox tail. Return only the successor result, then deliver predecessor Reply Directives. Debug history for each chain member must report its chain ID and order without changing ordinary Turn history. Successor failure, cancellation, or timeout must preserve the committed predecessor, keep the server alive, and permit later work.
- **kind:** ordering
- **status:** active

### jido.agent_server.handoff.I2 — Durable Handoff receipts

- **scope:** `Jido.AgentServer`, `Jido.AgentServer.DurableTurn`, `Jido.Persistence.Record`
- **must:** Commit the predecessor and its accepted successor intent in one saved Agent revision. Keep one chain ID, increase chain order, and save the exact released successor receipt before the live successor can start. A released receipt must keep the successor Instruction fingerprint, admitted Signal, prepared Plugin input, caller context, and fresh absolute expiry. Recovery can resume only a compatible released successor. Recovery must settle an accepted but unreleased intent as failed because predecessor effects are indeterminate and cannot be replayed. Cancellation before successor start must save a terminal receipt. Persistence writes must not block committed reads.
- **kind:** ordering
- **status:** active
