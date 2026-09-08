> Target seam design. This document is pending approval.

# Persistence design

All requirements and decisions in this document are recommended targets. EARS
syntax does not mean that the user approved a requirement. Code defines current
behavior until an approved target is implemented.

## Scope and owner

- Owner: `Jido.Persistence` and `Jido.Persistence.Adapter`.
- In scope: durable record algebra, key derivation, record format, revisions,
  load, create, write, logical delete, adapter controls, serialization checks,
  and recovery evidence.
- Out of scope: Agent checkpoint content, Agent Ref fields, definition authoring,
  candidate evaluation, Directive settlement, process restart policy, storage
  clients, discovery, placement, leases, multi-Agent transactions, and durable
  workflow history.
- Adjacent owners: seam 01 owns Agent checkpoints. Seam 03 owns Agent Ref. Seam
  05 owns Plugin state conversion. Seam 06 owns commit order. Seam 08 owns
  Agent Server lifecycle. Seam 10 owns runtime topology. Seam 12 owns public
  errors.

## Model

Persistence has two separate data boundaries:

```text
Agent-owned checkpoint map
  -> Persistence-owned durable record
  -> safe external-term binary
  -> Adapter-owned atomic byte storage
```

An Agent checkpoint represents one Agent value. It can use the default format
or complete custom `checkpoint/2` and `restore/2` callbacks. A durable record
adds identity, Agent module, definition revision when available, record kind,
state revision, and outer format. The adapter sees only a binary key, expected
binary or `:not_found`, and new binary.

The target record algebra has two values:

| Kind | Required meaning | Excluded data |
| --- | --- | --- |
| Active record | Exact Agent Ref, Agent module, optional definition revision, nonnegative state revision, and checkpoint | PID, runtime location, task, Directive batch, adapter client |
| Tombstone | Exact Agent Ref and last known nonnegative state revision | Checkpoint, Agent state, process status |

Hibernate is an Agent Server process transition. It does not add a durable
record state. An active record does not prove that a process is live.

Four revisions remain separate:

- record format version controls the outer durable map;
- checkpoint format version belongs to the Agent callback;
- definition revision identifies module-owned Agent meaning;
- state revision is the Agent Server commit revision used by persistence.

The target keeps exact-byte CAS. It does not add an opaque storage-version token
or record-valued instance callback. Stable Ref keys replace legacy module-based
keys only through an approved mixed-version migration.

## Requirements

### Ownership and adapter boundary

`PERS-REQ-001`: The Persistence boundary shall own durable Agent key
derivation, record meaning, record encoding, record validation, and state
revision checks.

`PERS-REQ-002`: The persistence adapter shall store binary keys and binary
values without inspecting Agent checkpoint or record meaning.

`PERS-REQ-003`: The persistence adapter shall provide `get/2` and
`compare_and_swap/4` as its required runtime operations.

`PERS-REQ-004`: When an adapter uses a client or storage process, the host
application shall supervise that process outside Jido.

`PERS-REQ-005`: While current adapter maintenance APIs remain supported, the
built-in adapters shall keep `put/3` and `delete/2` available without using
them for normal Agent commit or logical deletion.

### Checkpoint and record boundary

`PERS-REQ-006`: When Persistence saves an Agent, the Agent boundary shall
produce the checkpoint before Persistence builds the durable record.

`PERS-REQ-007`: When Persistence builds an active record, it shall keep the
Agent checkpoint as an opaque plain map inside the record.

`PERS-REQ-008`: When Persistence builds an active record, it shall store Agent
identity, Agent module, definition revision when available, and state revision
outside the checkpoint.

`PERS-REQ-009`: When Persistence builds a tombstone, it shall exclude the Agent
checkpoint and Agent state.

`PERS-REQ-010`: When a value enters a durable record, the Persistence boundary
shall reject a PID, port, reference, function, improper list, or non-byte-
aligned bitstring at any depth before adapter work starts.

### Revisions and compare-and-swap

`PERS-REQ-011`: When an Agent Server saves a successful Turn, the Persistence
boundary shall require the proposed state revision to equal the committed state
revision plus one.

`PERS-REQ-012`: When Persistence replaces a record, the adapter shall compare
the complete expected bytes and write the complete proposed bytes as one atomic
operation.

`PERS-REQ-013`: When Persistence creates a record, the adapter shall write it
only if the key is absent at the same atomic operation.

`PERS-REQ-014`: If the expected bytes do not match, then the adapter shall
return `{:error, :conflict}` without changing the stored value.

`PERS-REQ-015`: When a direct save proposes the exact stored record at the same
state revision, the Persistence boundary shall accept the write as idempotent.

`PERS-REQ-016`: If a direct save proposes different record content without a
higher state revision, then the Persistence boundary shall return a conflict
without adapter write work.

### Adapter results and errors

`PERS-REQ-017`: When adapter option validation rejects an operation before
storage work starts, the Persistence boundary shall return the defined invalid-
options error.

`PERS-REQ-018`: When adapter CAS reports an expected-value mismatch, the
Persistence boundary shall classify the result as a confirmed conflict.

`PERS-REQ-019`: When adapter CAS rejects a documented preflight limit before a
write starts, the Persistence boundary shall classify the result as a confirmed
rejection.

`PERS-REQ-020`: If adapter CAS raises, throws, exits, returns an invalid value,
or returns a failure outside the confirmed conflict and rejection set, then the
Persistence boundary shall classify the write as indeterminate.

`PERS-REQ-021`: When an adapter control reaches a public Jido persistence
operation, the Persistence boundary shall convert it to the approved seam-12
`PersistenceError` code.

`PERS-REQ-022`: If a required persistence write returns any error, then the
Agent Server shall remove that activation's write authority before it admits
another Turn.

### Create, load, write, and delete lifecycle

`PERS-REQ-023`: Where persistence is configured, when a new Agent activation
starts from supplied state, the Agent Server shall perform a create-only
revision-zero write before it reports readiness.

`PERS-REQ-024`: Where `restore: :if_found` is configured, when no active record
exists, the Agent Server shall create the supplied revision-zero Agent before
it reports readiness.

`PERS-REQ-025`: Where `restore: :required` is configured, if no active record
exists, then the Agent Server shall fail startup without creating a record.

`PERS-REQ-026`: Where `restore: false` is configured, when storage already
contains an active record or tombstone for the identity, the Agent Server shall
fail the create-only write without overwriting the stored value.

`PERS-REQ-027`: If the initial write is not confirmed, then the Agent Server
shall not publish the activation as ready.

`PERS-REQ-028`: If the initial write is not confirmed, then the Agent Server
shall stop every provisional Plugin runtime started for that activation.

`PERS-REQ-029`: When Persistence loads an active record, it shall validate the
complete outer record before it calls Agent restore.

`PERS-REQ-030`: When Agent restore returns an Agent, the Persistence boundary
shall verify the restored Agent identity and module before startup can continue.

`PERS-REQ-031`: Where a saved definition revision is present, when Persistence
loads an active record, it shall reject a mismatch before the Agent becomes
live.

`PERS-REQ-032`: When normal durable deletion targets an active record, the
Persistence boundary shall replace the exact active bytes with a tombstone by
CAS.

`PERS-REQ-033`: When normal durable deletion targets an absent identity, the
Persistence boundary shall create a revision-zero tombstone by CAS.

`PERS-REQ-034`: When Persistence loads a tombstone, it shall return the defined
deleted persistence error without calling Agent restore.

`PERS-REQ-035`: If deletion races with a newer commit, then the Persistence
boundary shall return a conflict and preserve the newer active record.

`PERS-REQ-036`: While a tombstone exists, the Persistence boundary shall reject
every normal create or save for that identity.

### Serialization and compatibility

`PERS-REQ-037`: When Persistence decodes a stored binary, it shall use safe
external-term decoding and reject malformed input as an invalid record.

`PERS-REQ-038`: If a loaded record has an unknown format, kind, identity,
module, revision, checkpoint shape, or portable-value result, then the
Persistence boundary shall fail closed without writing storage.

`PERS-REQ-039`: While legacy format-1 records are supported, the Persistence
boundary shall keep their current Agent restore path readable.

`PERS-REQ-040`: When durable identity moves to Agent Ref, the Persistence
boundary shall detect a legacy-key and Ref-key collision before it writes a new
record.

`PERS-REQ-041`: While legacy keys remain supported, the Persistence boundary
shall provide a documented dual-read, rewrite, rollback, and removal gate.

`PERS-REQ-042`: While complete custom Agent checkpoint callbacks remain
supported, the Persistence boundary shall preserve their plain-map output and
restore input without applying default checkpoint interpretation.

`PERS-REQ-043`: Where a complete custom Agent checkpoint is used, the
Persistence boundary shall bypass Plugin-owned slice conversion during the
first compatibility stage.

`PERS-REQ-044`: Where a Plugin Persistence facet is enabled, the Persistence
boundary shall give it only its paired Plugin-owned state value, format
context, and static options.

### Recovery and system boundaries

`PERS-REQ-045`: When a persistent Agent activation starts, the Agent Server
shall load the latest valid record for its known identity before it admits a
Turn.

`PERS-REQ-046`: When a live commit requires persistence, the Agent Server shall
make the candidate visible only after confirmed CAS success.

`PERS-REQ-047`: If a required persistence write is not confirmed, then the
Agent Server shall start no Directive from that Turn.

`PERS-REQ-048`: When an Agent Server hibernates or stops cleanly, the
Persistence boundary shall keep an active record and shall not encode process
liveness as durable state.

`PERS-REQ-049`: When runtime resources are rebuilt after restore, the
Persistence boundary shall keep PIDs, subscriptions, timers, clients, and
ownership bindings outside the durable Agent record.

`PERS-REQ-050`: When a Topology uses persistence, the Persistence boundary
shall store each member Agent through the normal single-Agent record contract
without claiming a multi-record atomic commit.

`PERS-REQ-051`: The Persistence adapter shall not provide Agent discovery,
activation, placement, lease, fencing, Directive replay, or durable mailbox
behavior as part of the core byte-storage contract.

## Public contract

The target keeps `Jido.Persistence.save_agent/3`, `load_agent/4`,
`load_agent_with_revision/4`, and `delete_agent/4` as the current direct
boundary during migration. Ref-first forms are additive after seam 03 and seam
09 approve the Ref and namespace binding. Existing instance defaults and
per-Agent override or disablement remain supported.

The required adapter callback set is:

```elixir
@callback get(binary(), keyword()) ::
            {:ok, binary()} | {:error, :not_found | term()}

@callback compare_and_swap(binary(), :not_found | binary(), binary(), keyword()) ::
            :ok
            | {:error, :conflict}
            | {:error, {:rejected, term()}}
            | {:error, :indeterminate | {:indeterminate, term()}}
```

`validate_options/1` remains optional. Built-in `put/3` and `delete/2` can stay
as public maintenance functions during migration, but they are not normal
Agent lifecycle operations.

Only `:ok` confirms a CAS write. `:conflict` and `{:rejected, reason}` confirm
that this operation did not write. Every other failure after CAS invocation is
indeterminate. Public functions normalize adapter controls through seam 12.

Physical tombstone purge is an application or provider maintenance operation.
Core does not expose it as normal Agent deletion. Reactivation of the same Ref
requires an approved purge and proof that old writers cannot run. A new Ref is
the safe default.

## Invariants

- `PERS-INV-001`: Agent checkpoint meaning and durable record meaning have
  separate owners and format versions.
- `PERS-INV-002`: One confirmed CAS changes one complete binary value.
- `PERS-INV-003`: A non-confirmed required write cannot produce visible live
  Agent state or post-commit Directive work.
- `PERS-INV-004`: Durable identity, Agent module, definition revision, state
  revision, and runtime location are separate values.
- `PERS-INV-005`: A tombstone preserves the conflict barrier after logical
  deletion.
- `PERS-INV-006`: Recovery reconstructs runtime resources from durable state;
  it does not persist runtime handles.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 08 Agent Server | Create, load, commit, hibernate, and delete receive one classified result and one authority rule. |
| 09 Jido instance | Instance defaults and per-Agent selection remain until an approved migration changes them. |
| 10 Runtime topology | Known Agents can restore independently; persistence does not provide discovery, placement, or exclusive cluster ownership. |
| 11 Topology control plane | Per-Agent records do not imply durable desired Topology or multi-record atomicity. |
| 12 Errors and contracts | Adapter controls remain internal and public operations use defined persistence errors. |
| 13 Observability | Events can report operation, result class, identity, and revision without record or checkpoint payloads. |
| Plugin capabilities | Pure owned-state conversion cannot inspect storage or change commit policy. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `PERS-DEC-001` | Which public storage boundary applies? | Keep the binary adapter below `Jido.Persistence`; add no record-valued instance callbacks. | Current adapters and per-Agent selection remain composable. |
| `PERS-DEC-002` | Which adapter operations are required? | Require `get/2` and CAS. Keep `put/3` and `delete/2` as temporary maintenance compatibility APIs. | Runtime writes cannot bypass record policy. |
| `PERS-DEC-003` | Which durable lifecycle values exist? | Use active records and compact tombstones only. | Hibernate remains a process operation. |
| `PERS-DEC-004` | What removes write authority? | Every required write error, including conflict. | Current conflict continuation must change with seams 06 and 08. |
| `PERS-DEC-005` | When is a new persistent Agent durable? | Before readiness, after provisional Plugin readiness. | Initial state survives a later VM failure subject to adapter guarantees. |
| `PERS-DEC-006` | How does identity change? | Use stable Ref only after collision-safe mixed-version migration is approved. | Module rename can stop changing identity without losing old records. |
| `PERS-DEC-007` | How does the outer format evolve? | Read legacy format 1 and write a new versioned active-or-tombstone format only after rollback gates exist. | Older releases cannot silently ignore tombstones. |
| `PERS-DEC-008` | How do custom checkpoints compose with Plugins? | Keep complete callbacks and bypass Plugin slice conversion first. | Current callbacks remain valid; the long-term composition stays open. |
| `PERS-DEC-009` | Where do Ecto and Bedrock adapters live? | Defer placement until conformance, optional-dependency, and package-boundary decisions are approved. | No unproved backend is claimed as shipped. |
