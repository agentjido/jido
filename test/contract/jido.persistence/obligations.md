---
modules:
  - Jido.Agent.Callback
  - Jido.Persistence
  - Jido.Persistence.Adapter
  - Jido.Persistence.AdapterOps
  - Jido.Persistence.AgentCheckpoint
  - Jido.Persistence.Checkpoint
  - Jido.Persistence.Identity
  - Jido.Persistence.Plugin
  - Jido.Persistence.Plugin.Context
  - Jido.Persistence.Record
  - Jido.Persistence.Snapshot
  - Jido.Persistence.Source
  - Jido.Persistence.Store
---

## Purpose

Protect portable Agent records and the shared storage boundary. This component
owns adapter configuration, durable identity, record data, snapshots, Plugin
state conversion, revisions, and logical deletion. It uses the strict
`Jido.PortableTerm` contract from `jido_action`.

The supported public boundary is `Jido.Persistence`,
`Jido.Persistence.Adapter`, `Jido.Persistence.Store`,
`Jido.Persistence.Plugin.Context`, and the bundled adapter modules. Snapshot,
record, identity, callback, and adapter-operation modules are internal.

It does not own live AgentServer recovery, commit publication, durable Flow
progress, or the private behavior of one storage backend.

## Obligations

### jido.persistence.I1 — Explicit adapter configuration

- **scope:** `Jido.Persistence.resolve_config/2`, `Jido.Persistence.Store.open/1`
- **must:** Accept a module or `{module, keyword}` adapter declaration. Treat nil and false as disabled. Resolve inheritance only from the selected Jido instance. Require binary reads and atomic compare-and-swap before an operation starts. Validate adapter options and contain validator faults.
- **why:** A storage operation needs one valid and explicit storage authority.
- **kind:** functional
- **status:** active

### jido.persistence.I2 — Stable durable identity

- **scope:** persistence keys and public Agent operations
- **must:** Identify one record by namespace, partition, and Agent ID. Do not include the Jido instance name or Agent module in the key. Require a stable namespace. Validate the record namespace, module, Agent ID, and partition before use.
- **why:** Different runtime names must not create different durable Agents.
- **kind:** persisted-format
- **status:** active

### jido.persistence.I3 — Byte read condition

- **scope:** `Jido.Persistence.Store.read/2`
- **must:** Accept only binary keys and adapter bytes. Return the exact bytes as the write condition, or return one nonempty opaque adapter token. Reject malformed adapter replies and contain callback faults.
- **why:** A later write must use the condition from the same validated read.
- **kind:** persisted-format
- **status:** active

### jido.persistence.I4 — Atomic write result

- **scope:** `Jido.Persistence.Store.compare_and_swap/4`
- **must:** Send one valid condition and one binary value to the adapter. Keep conflict and explicit rejection certain. Treat an explicit indeterminate result, unknown error, invalid reply, callback fault, throw, or exit as an unknown commit result. Do not retry inside the shared Store.
- **why:** The caller must know when storage can be ahead of its local state.
- **kind:** functional
- **status:** active

### jido.persistence.I5 — Exact record envelope

- **scope:** `Jido.Persistence.Record`
- **must:** Write the current exact active or tombstone record shape. Validate format, kind, identity, nonnegative revision, Agent version, optional durable Turn data, checkpoint shape, and portability in a fixed order. Read the supported legacy format without changing stored bytes. Reject other formats and extra or missing fields.
- **why:** Record data must have one strict and forward-safe boundary.
- **kind:** persisted-format
- **status:** active

### jido.persistence.I6 — Complete portable snapshot

- **scope:** `Jido.Persistence.snapshot/2`, `Jido.Persistence.restore/2`
- **must:** Save the complete accepted Agent definition and state as portable data. Restore from saved data without consulting the current source definition. Validate the snapshot envelope, restored Agent identity, definition, schema, and state.
- **why:** A checkpoint must not change when source code supplies new defaults.
- **kind:** persisted-format
- **status:** active

### jido.persistence.I7 — Code reference integrity

- **scope:** snapshot reference capture and restore
- **must:** Record and check the executable and schema code references required by the saved Agent. Reject a missing, unavailable, or changed required reference. Treat ordinary tuple data as data, not as a code reference.
- **why:** Saved data must not silently run different code.
- **kind:** persisted-format
- **status:** active

### jido.persistence.I8 — Explicit snapshot upgrade

- **scope:** `Jido.Persistence.upgrade/3`
- **must:** Run one explicit upgrade Action before old reference resolution. Accept only one portable snapshot and no Directives. Keep the Agent identity and origin fixed. Validate the upgraded snapshot and only its target references.
- **why:** Incompatible saved data needs a controlled conversion step.
- **kind:** functional
- **status:** active

### jido.persistence.I9 — Portable term boundary

- **scope:** snapshots, records, and converted Plugin state
- **must:** Use the public `Jido.PortableTerm` contract from `jido_action`. Accept nested portable values. Reject processes, ports, references, functions, improper lists, non-byte-aligned bitstrings, and other local runtime values. Return a bounded path to the rejected value and do not write invalid data.
- **why:** Durable data must be safe to move to another BEAM instance.
- **kind:** persisted-format
- **status:** active

### jido.persistence.I10 — Plugin-owned state conversion

- **scope:** default checkpoint dump and load
- **must:** Convert only the state value owned by each paired Plugin persistence facet. Use the saved Plugin version, options, record format, direction, and reason. Preserve unrelated domain and Plugin state. Validate loaded state against the owning Agent facet.
- **why:** Plugin storage codecs must not own the complete Agent.
- **kind:** functional
- **status:** active

### jido.persistence.I11 — Checkpoint callback containment

- **scope:** Agent and Plugin checkpoint callbacks
- **must:** Let a complete custom Agent checkpoint bypass default Plugin slice conversion. Contain callback faults and reject invalid callback results, nonportable output, identity changes, incomplete Plugin state, and invalid restored state. Do not write or return an invalid Agent.
- **why:** Extension callbacks must not weaken the storage boundary.
- **kind:** functional
- **status:** active

### jido.persistence.I12 — Operation options and revision rules

- **scope:** `create_agent/3`, `save_agent/3`, `load_agent/4`, `load_agent_with_revision/4`
- **must:** Reject malformed, duplicate, and operation-unsupported options before storage access. Create only revision zero and only when the key is absent. Load one active record, with its stored revision when requested. Save one complete Agent and optional durable Turn at the requested nonnegative revision. Enforce an expected revision when supplied. A failed read or validation must not become a write.
- **why:** Each successful write needs one clear predecessor.
- **kind:** ordering
- **status:** active

### jido.persistence.I13 — Tombstone deletion

- **scope:** `Jido.Persistence.delete_agent/4`
- **must:** Replace an active record with a compact tombstone through compare-and-swap. Keep its last revision. Create revision zero when deletion finds no record. Treat repeat deletion as success without another write. A tombstone fences later saves, and a delete race cannot replace a newer active record.
- **why:** Deletion must remain visible to stale writers and later restores.
- **kind:** ordering
- **status:** active

### jido.persistence.I14 — Opaque token and data privacy

- **scope:** token-based adapters and persistence telemetry
- **must:** Use a valid adapter token as the next compare-and-swap condition, even when stored bytes are equal. Do not put the token in record bytes, restored values, operation results, or telemetry. Do not put keys, stored bytes, or adapter options in Store telemetry.
- **why:** An opaque storage version is an authority value and can contain private data.
- **kind:** security
- **status:** active

### jido.persistence.I15 — Built-in adapter conformance

- **scope:** built-in persistence adapters
- **must:** Each active built-in adapter obeys the shared binary read and atomic compare-and-swap contract. Backend-specific configuration, maintenance, and fault mapping stay in that adapter's package tests.
- **why:** All bundled adapters must implement the same storage boundary.
- **kind:** functional
- **status:** active
