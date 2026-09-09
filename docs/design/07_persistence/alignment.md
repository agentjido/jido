> Seam alignment evidence. The implementation direction was selected on
> 2026-09-09. Stable Ref persistence was completed by seam 09 on 2026-09-10.

# Persistence alignment

## Status

- Implementation reviewed: 2026-09-09 on branch `v3-spike`.
- Prerequisites: package boundaries, portable errors, Agent checkpoints and
  versions, Agent Ref, Turn selection, owner-specific Plugin facets, and the
  commit authority rule are present.
- Alignment state: `Implemented, including stable namespaced identity`.

Persistence now owns a version-2 active-or-tombstone record, a closed binary
CAS boundary, revision-zero creation, definition checks, and default-checkpoint
Plugin conversion. The Agent Server confirms initial creation after Plugin
readiness and before its start call succeeds. Every required write error still
removes the activation's write authority.

Unnamed operations retain the compatible instance-module, Agent-module,
partition, and ID key. Namespaced operations use a stable Ref key and record
format 3. They read a lone legacy key and reject a legacy-plus-Ref collision.
They do not rewrite data across keys automatically.

This execution state is not approval of every requirement in the target
design.

## Selected architecture

Persistence has two data boundaries:

```text
Agent-owned checkpoint map
  -> Persistence-owned active or tombstone record
  -> safe external-term binary
  -> adapter-owned exact-byte CAS
```

`Jido.Persistence.Adapter` requires only `get/2` and
`compare_and_swap/4`. The compatible `put/3` and `delete/2` callbacks are
optional maintenance operations. Normal Agent save and delete paths do not use
them.

Version-2 active records have these exact fields:

```text
format, kind, instance, agent_module, agent_vsn, agent_id,
partition, revision, checkpoint
```

Version-2 tombstones have these exact fields:

```text
format, kind, instance, agent_module, agent_id, partition, revision
```

A tombstone contains no checkpoint or Agent state. It keeps the last active
revision, or revision zero when deletion targets an absent key. Normal create
and save operations cannot replace it. Loading it returns
`{:error, :deleted}`. Physical purge is an adapter or provider maintenance
operation. Core does not use purge for normal Agent deletion.

## Lifecycle results

### Create and restore

- `restore: false` does not read a record. It performs a create-only
  revision-zero CAS after provisional Plugin readiness.
- `restore: :if_found` restores an active record. A missing record uses the
  supplied Agent and then performs the same create-only CAS.
- `restore: :required` restores an active record. A missing or deleted record
  fails startup and does not create a record.
- An existing active record or tombstone makes a new create conflict.
- A failed initial write makes the start call fail and stops the provisional
  Plugin runtime tree.

The Registry reserves the identity with value `:starting`. Public lookup and
listing expose it only after the initial write succeeds and Agent Server
publishes value `:ready`.

### Commit and write results

The Agent Server supplies its current revision as `:expected_revision`. The
adapter compares the complete stored bytes and writes the complete proposed
bytes as one operation.

Only `:ok` confirms a write. `{:error, :conflict}` confirms an exact-value
mismatch. `{:error, {:rejected, reason}}` confirms a documented preflight
rejection. An explicit indeterminate result, another error, a raise, a throw,
an exit, or an invalid callback result is indeterminate. The Agent Server stops
after every one of these required write errors.

### Delete

Delete reads and validates the current record, then replaces its exact bytes
with a compact tombstone by CAS. A concurrent newer commit makes the delete
conflict and preserves that active record. Repeated delete of a tombstone is
idempotent.

The Redis adapter applies its configured TTL to active records and tombstones.
Therefore, its stale-writer barrier lasts only as long as that TTL. Use no TTL,
or use an application maintenance policy that preserves the required fence.

### Checkpoint and Plugin composition

The Agent owns checkpoint meaning. Persistence owns the outer record. The
Agent `vsn` is copied outside the checkpoint and checked before Agent restore.

For a default checkpoint, each `Jido.Persistence.Plugin` facet receives only
its paired Agent-facet state value, a bounded format context, and its mapped
static options. Dump runs before record validation. Load runs after outer
record validation and before Agent restore. The facet cannot see an adapter,
record key, complete Agent state, process, or commit result.

A complete custom Agent checkpoint bypasses Plugin slice conversion. Its
wrapped plain-map payload stays opaque to Persistence. Legacy outer format-1
active records remain readable through their earlier restore path.

## Canonical source

| Source | Implemented contract |
| --- | --- |
| `lib/jido/persistence.ex` | Source resolution, key ownership, create, load, save, logical delete, revision rules, result classification, and adapter fault containment. |
| `lib/jido/persistence/record.ex` | Exact version-2 active and tombstone shapes, legacy format-1 validation, safe decoding, identity checks, and portability. |
| `lib/jido/persistence/checkpoint.ex` | Agent checkpoint order, bounded Plugin owned-slice dump and load, and custom-checkpoint bypass. |
| `lib/jido/persistence/adapter.ex` | Required binary get and CAS contract plus optional compatible maintenance callbacks. |
| `lib/jido/agent_server.ex` | Restore selection, revision-zero create after Plugin readiness, durable commit, and authority loss after write failure. |
| `lib/jido/agent_server/state.ex` | Explicit initial-persistence phase for new, restored, and nonpersistent activations. |
| `lib/jido/topology/controller/activation.ex` | Existing durable members use required restore; missing members use create-only revision zero. |
| `lib/jido/persistence/ets.ex` | Process-local exact-byte CAS. |
| `lib/jido/persistence/file.ex` | One-BEAM file CAS with atomic rename and no file-system sync claim. |
| `lib/jido/persistence/redis.ex` | One-command Redis CAS with application-owned client and TTL policy. |
| `lib/jido/persistence/bedrock.ex` | Bedrock `0.7.x` transaction mapping, exact-byte CAS, size and option validation, isolated outer transactions, and conservative write-result classification. |
| `lib/jido/persistence/ecto.ex` | One-statement PostgreSQL or SQLite CAS with an application-owned Ecto repository and schema. |

## Executable evidence

| Evidence | Result |
| --- | --- |
| `test/jido/persistence/record_lifecycle_test.exs` | Exact version-2 shapes, revision-zero startup, restore policies, active and missing delete, delayed-writer fencing, delete-versus-commit race, legacy reads, definition checks, and fail-closed future records. |
| `test/jido/persistence/plugin_integration_test.exs` | Default checkpoints convert only the paired owned state. Complete custom checkpoints bypass conversion. |
| `test/jido/persistence/adapter_conformance_test.exs` | ETS, File, Redis, Ecto, and Bedrock pass one required binary get and exact-byte CAS suite, including concurrent winners. |
| `test/jido/persistence/bedrock_test.exs` | Bedrock option, limit, exact-byte, conflict, and indeterminate-result branches pass with a deterministic transaction repo. |
| `test/jido/persistence/bedrock_integration_test.exs` | A real single-node Bedrock `0.7.x` cluster passes concurrent CAS, Jido record save, clean restart restore, and logical delete. |
| `test/jido/persistence/ecto_test.exs` | Ecto schema validation, exact bytes, same-value CAS, complete Jido record lifecycle, and database and constraint fault classification pass against SQLite. |
| `test/jido/persistence/adapter_test.exs` | An adapter with only get and CAS is valid. Option validation failures remain contained. |
| `test/jido/persistence_test.exs` | Direct lifecycle, revision rules, closed CAS results, write faults, live commit, hibernate, thaw, and stale activation behavior pass. |
| `test/jido/persistence/indeterminate_write_test.exs` | Stored lost-reply and explicit indeterminate writes stop authority and do not start Directives. |
| `test/jido/agent_server/plugin_lifecycle_test.exs` | A rejected initial write stops its provisional Plugin runtime. |
| `test/jido/agent_server/effect_recovery_test.exs` | Failed intent and acknowledgement writes stop the activation while confirmed records remain recoverable. |
| `test/jido/plugin/scheduler/occurrence_recovery_test.exs` | Scheduler intent and result failures preserve the last confirmed record for restore. |
| `test/jido/topology/controller_test.exs` and `test/jido/topology/controller/composition_runtime_test.exs` | Persistent members and Bus subscriptions restore after controller restart under the create-only rule. |
| `test/examples/99_research/99_13_durable_delete` | The durable-delete acceptance example now passes without a skip. |

## Requirement disposition

| Requirement set | State | Evidence or owner |
| --- | --- | --- |
| `PERS-REQ-001` to `PERS-REQ-010` | `Proven` | Persistence owns the record above binary adapters. Version-2 shapes and portable data are checked. |
| `PERS-REQ-011` to `PERS-REQ-016` | `Proven` | Live and direct revision rules use exact-byte CAS. |
| `PERS-REQ-017` to `PERS-REQ-020` | `Proven` | Option validation and the closed CAS classification have focused tests. |
| `PERS-REQ-021` | `Compatible control retained` | Public calls keep current raw controls and existing structured callback errors. A new error family is not added. |
| `PERS-REQ-022` | `Proven` | Seam 06 and current recovery tests show authority loss after every required write error. |
| `PERS-REQ-023` to `PERS-REQ-028` | `Proven with seam 08 publication` | Initial CAS and Plugin cleanup pass. Public Registry lookup stays hidden until the entry is `:ready`. |
| `PERS-REQ-029` to `PERS-REQ-038` | `Proven` | Outer validation, restored identity, definition revision, tombstones, races, and safe decoding pass. |
| `PERS-REQ-039` | `Proven` | Legacy outer format-1 active records load. |
| `PERS-REQ-040`, `PERS-REQ-041` | `Proven by seam 09` | Namespaced operations use the Ref key, dual-read a lone legacy key, and reject a dual-key collision before a write. |
| `PERS-REQ-042` to `PERS-REQ-044` | `Proven` | Custom callback payloads stay opaque. Default Plugin owned-slice conversion is bounded. |
| `PERS-REQ-045` to `PERS-REQ-049` | `Proven` | Restore, commit order, failure stop, hibernate, and runtime reconstruction have focused evidence. |
| `PERS-REQ-050` | `Single-Agent contract proven; Topology integration remains with seams 10 and 11` | Persistence exposes no multi-record transaction claim. |
| `PERS-REQ-051` | `Proven` | The adapter has no discovery, placement, lease, replay, or mailbox API. |

## Compatibility and migration

- Public module-and-ID Persistence functions remain available.
- Existing instance defaults, per-Agent overrides, partitions, hibernate, and
  thaw remain available.
- Outer format-1 active records remain readable. Compatible unnamed writes use
  format 2. New namespaced writes use format 3.
- Older code cannot load format-2 records, but its fail-closed record check also
  prevents it from overwriting a format-2 tombstone through normal save.
- A namespaced operation probes the stable and compatible keys. A lone legacy
  key remains on that key. Both keys cause a collision error. The adapter
  cannot atomically rewrite two keys, so Jido does not rewrite automatically.
  An older release cannot read format 3. Downgrade after the first namespaced
  write is unsupported.
- `put/3` and `delete/2` remain optional maintenance callbacks. Normal durable
  lifecycle code uses only get and CAS.
- Ecto applications must add Ecto SQL and a supported driver, supervise their
  repository, and migrate the binary `key`, `value`, and `write_token` table
  before Jido starts. Jido does not move existing data into this table.
- Tombstone purge and same-identity reactivation are not normal Core
  operations. A new Ref is the safe default after durable deletion.
- Bedrock write transactions set `retry_limit: 0`. This prevents an automatic
  retry after an unknown commit result from becoming a false confirmed
  conflict. A Bedrock resolver abort maps to conflict. Other write failures
  stay indeterminate. The host owns strict durability configuration and
  Bedrock cluster supervision.
- The host adds Bedrock Raft with `>= 0.9.7 and < 0.10.0` and `override: true`.
  Bedrock `0.7.x` has a broad dependency requirement, but it uses the `0.9.x`
  client API. The explicit host constraint prevents an incompatible `0.10.x`
  selection.

## Remaining owner work

| Seam | Required follow-up |
| --- | --- |
| 08 Agent Server | Preserve `:starting` identity reservation and publish `:ready` only after revision-zero creation is confirmed. |
| 09 Jido instance | Complete. It binds namespace, supplies the Ref facade, applies the mixed-key rule, and exposes tombstone delete for an inactive Ref. |
| 10 Runtime topology | Consume revision-zero activation without adding discovery or lease meaning to persistence. |
| 11 Topology control plane | Keep desired Topology and multi-Agent reconciliation outside per-Agent records. |
| 13 Observability | Add bounded operation and result-class evidence without checkpoint payloads or adapter secrets. |
| Provider owners | Define tombstone retention and purge tools. Bedrock key and value limits and its clean-restart evidence are implemented. Deployment recovery claims remain with the Bedrock cluster owner. |

## Completion gate for this seam

- [x] Binary get and exact-byte CAS are the required runtime adapter boundary.
- [x] New writes use exact version-2 active or tombstone records.
- [x] Revision-zero creation completes before the start call succeeds.
- [x] Active restore, live commit, hibernate, and thaw preserve state revision.
- [x] Every required write error removes activation authority.
- [x] Logical deletion fences delayed writers and concurrent newer commits.
- [x] Legacy format-1 active records remain readable.
- [x] Agent definition revision is checked before restore.
- [x] Default Plugin state conversion stays within the paired owner slice.
- [x] Complete custom checkpoints bypass Plugin conversion.
- [x] ETS, File, Redis, Ecto, and Bedrock pass one shared get-and-CAS conformance suite.
- [x] Stable Ref key migration rules are implemented in seam 09.
- [x] Provisional Registry visibility is decided in seam 08.
- [ ] The full target design has user approval.
