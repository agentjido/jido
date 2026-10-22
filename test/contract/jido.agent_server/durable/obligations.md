---
modules:
  - Jido.AgentServer.Durable
---

## Purpose

Protect persistence-backed AgentServer state coordination. This component owns
the points where a live Agent becomes durable or is rebuilt from durable state.
It does not own persistence record formats, local activation checkpoints,
Plugin callback rules, or durable Flow progress.

The public boundary is `Jido.AgentServer.hibernate/2`, `snapshot/2`, and
`upgrade/3`. `Jido.AgentServer.Durable` is internal. Persistence configuration
uses AgentServer options; this component has no DSL.

## Obligations

### jido.agent_server.durable.I1 — Explicit durable configuration

- **scope:** AgentServer startup and persistent control
- **must:** Keep persistence disabled by default. Accept an explicit adapter or inherit the selected Jido instance adapter. Require an activation and a stable instance namespace. Validate a finite persistence timeout, create or restore mode, and the persistence requirement for idle hibernation before startup.
- **why:** Durable authority must be explicit and bounded.
- **kind:** functional
- **status:** active

### jido.agent_server.durable.I2 — Revision-zero creation

- **scope:** persistent AgentServer startup with create mode
- **must:** Bind the complete initial Agent, assign stable persistent topology identities, and create revision zero before Plugin startup, readiness, or accepted work. Do not replace an existing record.
- **why:** A new persistent activation needs one stored starting point.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I3 — Explicit restore

- **scope:** persistent AgentServer startup with restore mode
- **must:** Load outside the server before readiness. Fail on missing, deleted, corrupt, incompatible, or unavailable data. Validate the complete Agent, fixed identity, exact definition origin, and nonnegative revision before Plugin startup. Do not fall back to supplied fresh state. Hand any stored Turn receipt to the durable Turn owner.
- **why:** Restore must use saved state as its authority.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I4 — Plugin state reconstruction

- **scope:** durable startup and recovery
- **must:** Restore Plugin-owned domain state through the checkpoint conversion contracts before Plugin Init. Give new resources the saved state and revision. Use the saved definition's Plugin declarations and options. Do not save runtime handles or replay commit hooks and Directives.
- **why:** Runtime Plugin resources must be derived from stored domain state.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I5 — Required commit before publication

- **scope:** successful persistent AgentServer work
- **must:** Save the complete accepted candidate with the current expected revision and next revision before the local checkpoint, success reply, Plugin hooks, or Directives. Run the save outside the server with its own finite deadline. Hold new work and keep committed reads available. Caller wait timeout and cancellation must not cancel an accepted save.
- **why:** The durable record must exist before success becomes visible.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I6 — Failed or uncertain write

- **scope:** required persistent writes
- **must:** On conflict, rejected write, adapter fault, invalid result, task loss, or uncertain write, publish no success and end the activation after owned cleanup. Treat deadline expiry and a late result as indeterminate. Run no post-commit callback or Directive and do not continue without persistence.
- **why:** An activation without durable authority must not accept more work.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I7 — Durable recovery authority

- **scope:** persistent worker replacement
- **must:** Reload durable storage before admission on every worker replacement. Restore a confirmed write that was not published to the local checkpoint or caller. Replace the activation checkpoint with the validated stored revision and do not replay the interrupted Turn.
- **why:** Durable storage can be ahead of local runtime state.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I8 — Portable save boundary

- **scope:** durable create and commit
- **must:** Apply Agent and Plugin checkpoint conversions and require a portable stored representation. Keep local schema-permitted values valid for memory-only work. A nonportable durable value must fail without commit publication.
- **why:** Process-local handles must not enter durable records.
- **kind:** persisted-format
- **status:** active

### jido.agent_server.durable.I9 — Confirmed hibernation

- **scope:** `Jido.AgentServer.hibernate/2`
- **must:** Require persistence and an activation. Quiesce first, then save the current Agent and current revision in owned work within the smaller control and persistence budgets. Return success only after save confirmation, Plugin shutdown, and activation DOWN. A known no-write failure restores prior admission. A conflict, uncertainty, task loss, or deadline keeps admission blocked across recovery and forbids resume.
- **why:** Hibernation must have a confirmed storage and shutdown boundary.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I10 — Persistent idle hibernation

- **scope:** `idle_policy: :hibernate`
- **must:** Require configured persistence and use the same current-revision save-and-stop boundary as explicit hibernation. A failed automatic save must close admission and must not start an automatic retry loop.
- **why:** Idle shutdown must not use a weaker durable boundary.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I11 — Atomic live snapshot

- **scope:** `Jido.AgentServer.snapshot/2`
- **must:** Read the complete committed Agent and revision in one server event. Do not expose provisional startup state. A failed operation must preserve both values. Keep portable conversion as a separate persistence operation.
- **why:** Upgrade and persistence work need one consistent live value.
- **kind:** functional
- **status:** active

### jido.agent_server.durable.I12 — Snapshot upgrade coordination

- **scope:** `Jido.AgentServer.upgrade/3`
- **must:** Serialize an explicit snapshot upgrade Action with Turns. Run portable snapshot conversion and upgrade outside the server. Reject malformed results and returned Directives. Hand the restored target to composition validation, then use the normal revision, durable save, local checkpoint, and reconciliation boundaries. Preserve the accepted Agent and revision on rejection and restore an accepted durable upgrade after recovery.
- **why:** A definition upgrade must use the same accepted-state boundaries as other work.
- **kind:** ordering
- **status:** active

### jido.agent_server.durable.I13 — Public durable API

- **scope:** `Jido.AgentServer.hibernate/2`, `snapshot/2`, `upgrade/3`
- **must:** Keep the exact durable operations on the documented `Jido.AgentServer` facade. Document and type atomic snapshots, upgrade options, results, and errors. Keep durable coordination internal. Do not add a durable DSL or expose adapter coordination.
- **why:** Users need one stable durable boundary without access to storage orchestration internals.
- **kind:** functional
- **status:** active
