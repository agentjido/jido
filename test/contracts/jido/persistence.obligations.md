---
modules:
  - Jido.Persistence
  - Jido.Persistence.Checkpoint
  - Jido.Persistence.Codec
  - Jido.Persistence.Codec.JSON
  - Jido.Persistence.Codec.Term
  - Jido.Persistence.Config
  - Jido.Persistence.Inspector
  - Jido.Persistence.Plugin
  - Jido.Persistence.Record
  - Jido.Persistence.Snapshot
  - Jido.Persistence.Store
  - Jido.Persistence.WakeStore
  - Jido.Instance.Wake
---

## Purpose

Protect portable Agent records and the shared storage boundary. This component
owns adapter configuration, durable identity, record data, snapshots, Plugin
state conversion, revisions, codecs, inspection, and logical deletion. One
instance profile selects a binary Store and one persistence codec.

The supported public boundary is `Jido.Persistence`, `Jido.Persistence.Store`,
and the bundled adapter modules. Persistence Plugin callbacks use the generic
`Jido.Plugin.Context.Persistence` record. Snapshot, record, identity, callback,
and adapter-operation modules are internal.

It does not own live AgentServer recovery, commit publication, durable Flow
progress or the private behavior of one storage backend. It owns the durable
wake record layout and wake recovery health, but not wait semantics.

## Obligations

### jido.persistence.I1 — Explicit adapter configuration

- **scope:** `Jido.Persistence.resolve_config/2`, `Jido.Persistence.Store.open/1`
- **must:** Accept a module or `{module, keyword}` Store declaration as shorthand for the Term codec. Accept one unique `store:` and `codec:` profile. Treat nil and false as disabled. Resolve inheritance only from the selected Jido instance. Use that one profile for Agent, Flow, and wake records. Reject a per-Agent Store replacement. Require a stable namespace and create or validate its exact codec and record-layout manifest before durable work starts.
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

### jido.persistence.I4 — Atomic write and delete result

- **scope:** `Jido.Persistence.Store.compare_and_swap/4`, `Jido.Persistence.Store.delete/2`
- **must:** Send one valid condition and one binary value to the adapter. Keep conflict and explicit rejection certain. Apply the same result rules to physical delete. Treat an explicit indeterminate result, unknown error, invalid reply, callback fault, throw, or exit as an unknown write result. Do not retry inside the shared Store.
- **why:** The caller must know when storage can be ahead of its local state.
- **kind:** functional
- **status:** active

### jido.persistence.I5 — Exact record envelope

- **scope:** `Jido.Persistence.Record`
- **must:** Read and write the exact V3 active or tombstone record shape under the V3 key prefix. Encode it through the instance codec. Validate format, kind, identity, nonnegative revision, Agent version, optional durable Turn data, checkpoint shape, and portability in a fixed order. Reject every other format and extra or missing fields without changing stored bytes. Do not add a runtime or inspection compatibility path.
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
- **must:** Use the compact Term persistence codec by default and the bounded tagged JSON codec only when selected by the instance profile. Accept nested portable values. Reject processes, ports, references, functions, improper lists, non-byte-aligned bitstrings, and other local runtime values. Restore atoms only when they exist in the compatible application release. Return a bounded path to a rejected checkpoint value and do not write invalid data.
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

### jido.persistence.I15 — Built-in adapter conformance and inspection

- **scope:** built-in persistence adapters
- **must:** Each active built-in adapter obeys the shared binary read, atomic compare-and-swap, mandatory delete, and strict unique-option contract. Redis does not accept automatic TTL. Ecto rejects writes inside an outer Repo transaction. Optional scans are paged, prefix-bounded, and use bounded page work. Runtime recovery never uses scan. Inspection tasks load configuration without starting the application or Agents. They safely decode only V3 records and produce JSON. Exact inspection needs explicit full mode for saved values. JSONL export redacts Agent state and projects prepared values, fact values, and execution batches to metadata and shape by default.
- **why:** All bundled adapters must implement the same durability boundary while developer inspection stays above the byte Store.
- **kind:** functional
- **status:** active

### jido.persistence.I16 — Atomic stored Agent upgrade

- **scope:** `Jido.Persistence.upgrade_agent/5`
- **must:** Read one active record and run one explicit upgrade Action before old code reference resolution. Refuse a nonterminal durable Turn. Write the complete upgraded Agent at the next revision with the condition from that read. Keep stored bytes unchanged after validation, Action, encoding, or compare-and-swap failure.
- **why:** An inactive durable Agent needs a safe code and data evolution path.
- **kind:** ordering
- **status:** active

### jido.persistence.I17 — Sharded wake durability and recovery health

- **scope:** `Jido.Persistence.WakeStore`, `Jido.Instance.Wake`
- **must:** Store timed wakes in deterministic one-minute buckets and 64 shards. Keep a small active index that records each shard generation. Confirm the shard and index before the Agent wait record commits. Do not remove a newer generation during concurrent cleanup. Retry failed startup reads before readiness. Retry failed cleanup with an observable warning. Delete a delivered or stale wake without delivering it again. Do not use Store scan for runtime recovery.
- **why:** A committed timed wait must remain reachable across crashes, cleanup races, and temporary Store failures.
- **kind:** ordering
- **status:** active
