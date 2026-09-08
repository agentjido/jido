> Seam alignment plan. This document is pending approval.

# Persistence alignment

## Status

- Design reviewed: 2026-09-08. All documents in this seam are pending approval.
- Code reviewed: `40ba9ff9c6e9dac6806f5c0adb146b58e14741a7` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md),
  [05 Plugins](../05_plugins/alignment.md), and
  [06 Commit and effects](../06_commit-and-effects/alignment.md). All were used
  as pending draft prerequisites.
- Related serialization input: [02 Agent authoring](../02_agent-authoring/design.md).
- Alignment state: `Blocked`.

The state is blocked because prerequisite decisions are pending and the target
write-authority, identity, record, tombstone, and Plugin composition rules are
not approved. This file is alignment input. It is not a formal implementation
plan.

## Inputs and evidence

### Design inputs

- [Jido V3 vision](../VISION.md): Jido owns portable persistence contracts and
  record revision rules. The adapter owns atomic byte storage. The application
  owns the storage service.
- [Overview design](../00_overview/design.md): proposes initial active records,
  authority loss after any write error, tombstones, portable records, and no
  durable runtime handles.
- [Package-boundary design](../90_package-boundaries/design.md): keeps record
  meaning in Jido and the binary adapter as a distinct host-owned integration.
- [Errors design](../12_errors-and-contracts/design.md): keeps raw adapter
  controls inside the protocol and requires public `PersistenceError` values.
- [Agent design](../01_agent/design.md): keeps plain-map default and custom
  checkpoints and separates checkpoint, definition, state, and storage versions.
- [Identity design](../03_agent-identity/design.md): proposes Ref as durable
  identity and assigns legacy key migration to this seam.
- [Turn design](../04_turn-evaluation/design.md): ends before persistence and
  gives the commit boundary one validated candidate.
- [Plugin design](../05_plugins/design.md): permits pure owned-slice conversion
  but requires a custom-checkpoint compatibility rule.
- [Commit design](../06_commit-and-effects/design.md): requires confirmed
  persistence before visibility or Directives and proposes authority loss after
  every write error.
- [Target design](design.md): consolidates the recommended persistence target.

### Canonical code

| Evidence | Current behavior |
| --- | --- |
| `lib/jido/persistence.ex:1-16,59-160` | Persistence owns key, record, checkpoint call, restore call, revision, and adapter containment. Public functions use module, ID, instance, and partition. |
| `lib/jido/persistence.ex:200-282` | Adapter validation requires `get`, `put`, CAS, and `delete`. Save reads, validates revision, and uses exact expected bytes. |
| `lib/jido/persistence.ex:284-371` | Format-1 active maps are encoded with Erlang external terms, checked for portability, decoded with `[:safe]`, and checked for identity and shape. |
| `lib/jido/persistence.ex:386-430` | Adapter errors pass through. Exceptions and invalid results become `ExecutionError`; there is no `PersistenceError`. |
| `lib/jido/persistence/adapter.ex:1-46` | The public byte behavior includes four operations. Its docs treat only explicit indeterminate results, exceptions, and invalid replies as uncertain. |
| `lib/jido/persistence/ets.ex:22-67` | ETS provides atomic create and replacement plus unconditional put and delete. Data ends with the BEAM. |
| `lib/jido/persistence/file.ex:27-103` | File CAS uses a one-BEAM global lock and atomic rename. It does not call file or directory sync. |
| `lib/jido/persistence/redis.ex:52-112` | Redis CAS uses one `EVAL`; command errors and invalid CAS replies are indeterminate. TTL applies to stored values. |
| `lib/jido/agent.ex:370-423,509-598` | Agent owns default and complete custom checkpoint maps. Default version 1 includes complete combined state. Restore validates module and state. |
| `lib/jido/plugin.ex:67-102` | No Plugin checkpoint or restore callback exists. |
| `lib/jido.ex:70-107,473-528,631-684` | An instance supplies an adapter default. Per-Agent selection remains. Hibernate and thaw use the existing Server path. There is no logical instance delete facade. |
| `lib/jido/agent_server/options.ex:47-53,377-401` | Persistence can inherit, override, or disable. Restore is `false`, `:if_found`, or `:required`. There is no persistence operation limit. |
| `lib/jido/agent_server.ex:438-533,2874-2905` | Restore and Plugin readiness complete before startup success. A new Agent gets no revision-zero durable write. |
| `lib/jido/agent_server.ex:623-630,1493-1594` | Hibernate and Turn commit save before state change. Conflict can follow error policy and keep the Server active. Uncertain writes stop it. |
| `lib/jido/agent_server.ex:2915-2950` | Server saves with its current expected revision. Hibernate and clean stop keep an active checkpoint shape. |
| `lib/jido/topology/controller/activation.ex:9-52` | Topology restores known member Agents independently through the instance adapter. |

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/persistence_test.exs:259-279,422-505` | Live commit persists revision 1; stale and same-revision changed writes conflict; two writers have one winner. |
| `test/jido/persistence_test.exs:305-357` | A confirmed conflict can leave a stale Server active under its error policy. |
| `test/jido/persistence_test.exs:359-404` | Thaw and automatic restore work. Current delete returns later `:not_found`. |
| `test/jido/persistence_test.exs:406-420` | Corrupt bytes fail load and are not overwritten by save. |
| `test/jido/persistence/adapter_test.exs:59-110` | Adapter declarations and option validator faults are checked. All four callbacks are required. |
| `test/jido/persistence/indeterminate_write_test.exs:35-115` | Confirmed CAS permits commit. Indeterminate or lost-reply writes prevent Directives and later stale evaluation. |
| `test/jido/persistence/checkpoint_identity_test.exs:14-32` | Outer and restored Agent ID mismatches fail. |
| `test/jido/persistence/checkpoint_portability_test.exs:15-49` | Portable nested data round trips. Nested PID and improper-list data fail before store or after load. |
| `test/jido/persistence/ets_test.exs:17-52` | ETS exact-byte create, replacement, conflict, and concurrent winner behavior pass. |
| `test/jido/persistence/file_test.exs:18-49` | File exact-byte CAS and one-BEAM concurrency behavior pass. |
| `test/jido/persistence/redis_test.exs:63-89,138-147` | Controlled tests prove one EVAL command and result mapping, not a real Redis recovery claim. |
| `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs:13-30` | Existing revisions reject stale writers. The tombstone fencing target remains skipped. |
| `test/examples/99_research/99_15_state_migration/state_migration_test.exs:8-59` | A predeclared compatible state migration persists. It does not prove definition or Plugin restore migration. |
| `test/jido/topology/controller_test.exs:247-284` and `test/jido/topology/controller/composition_runtime_test.exs:222-245` | ETS-backed member state restores and runtime Bus resources rebuild when the application supplies the Topology again. |

## Retained baseline

- Persistence owns record meaning. Adapters own binary operations only.
- Exact-byte atomic CAS protects live commits from stale storage revisions.
- A confirmed write precedes live Agent replacement and Directive handling.
- An indeterminate or lost-reply write stops the current writer.
- Active records validate outer identity, restored Agent identity, revision,
  shape, and portable content.
- Default checkpoints include complete Agent and Plugin state. Complete custom
  Agent checkpoint and restore callbacks remain supported.
- Instance defaults can be replaced or disabled for one Agent.
- ETS, File, and Redis keep their documented current limits.
- Persistent restore rebuilds Plugin and Topology runtime resources instead of
  storing their process handles.
- Current direct, ID, PID, partition, hibernate, thaw, and adapter APIs remain
  supported until an approved migration replaces one.

## Gap register

| Gap | Requirements | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `PERS-GAP-001` | `PERS-REQ-001` to `PERS-REQ-005` | Persistence and adapter modules | Owner split works, but four callbacks remain required. | `Change, compatible` |
| `PERS-GAP-002` | `PERS-REQ-006` to `PERS-REQ-010` | Record and Agent checkpoint code | Checkpoint layering works. Target Ref, definition revision, tombstone, and complete portable-term set do not. | `Partial`; `Blocked` on seams 01, 03, and 12 |
| `PERS-GAP-003` | `PERS-REQ-011` to `PERS-REQ-016` | Save code and revision tests | Exact-byte CAS and direct revision rules work. Server next-revision ownership is spread across modules. | `Retain`; strengthen contract evidence |
| `PERS-GAP-004` | `PERS-REQ-017` to `PERS-REQ-021` | Adapter containment and error tests | There is no closed rejection set or public `PersistenceError`. Plain returned errors can look confirmed. | `Change`; `Blocked` on seam 12 |
| `PERS-GAP-005` | `PERS-REQ-022` | Server failure branch and stale-Server test | Only uncertain writes always remove authority. | `Conflict`; `Blocked` on seams 06 and 08 |
| `PERS-GAP-006` | `PERS-REQ-023` to `PERS-REQ-028` | Startup and restore code | A new persistent Agent reports ready without revision-zero storage. | `Missing`; `Blocked` on Agent Server lifecycle |
| `PERS-GAP-007` | `PERS-REQ-029` to `PERS-REQ-031` | Load validation and restore tests | Current validation works. Definition revision does not exist. | `Partial`; `Blocked` on seam 01 |
| `PERS-GAP-008` | `PERS-REQ-032` to `PERS-REQ-036` | Blind delete and skipped FA-05 test | No tombstone or durable deletion fence exists. | `Missing` |
| `PERS-GAP-009` | `PERS-REQ-037`, `PERS-REQ-038` | Safe decode and corrupt-record tests | Most current corruption checks work. Bitstring and future-kind cases need the approved error contract. | `Partial` |
| `PERS-GAP-010` | `PERS-REQ-039` to `PERS-REQ-041` | Format-1 key and identity code | No Ref key, dual read, collision check, rewrite, rollback, or removal gate exists. | `Blocked` on seams 03 and 09 |
| `PERS-GAP-011` | `PERS-REQ-042`, `PERS-REQ-043` | Custom Agent callback tests | Complete custom callbacks work. Plugin bypass is not needed until a facet exists. | `Proven` for current callback; target composition is `Deferred` |
| `PERS-GAP-012` | `PERS-REQ-044` | No Plugin Persistence facet | Owned-slice conversion does not exist. | `Deferred`; `Blocked` on seam 05 |
| `PERS-GAP-013` | `PERS-REQ-045` to `PERS-REQ-048` | Server restore and commit tests | Restore and commit order work. Creation and all-error authority do not. | `Partial` |
| `PERS-GAP-014` | `PERS-REQ-049`, `PERS-REQ-050` | Plugin and Topology recovery tests | Runtime reconstruction and per-Agent restore work only for current covered paths and ETS Topology tests. | `Partial` |
| `PERS-GAP-015` | `PERS-REQ-051` | Adapter API and package boundaries | Core has no discovery or lease API. The exclusion needs a public boundary check. | `Proven` in current API; release evidence is `Partial` |

## Disposition of superseded claims

This table covers the distinct claims in the removed persistence index, gap
analysis, instance proposal, and adapter proposal. Git history keeps the old
text.

| Superseded claim | Disposition | Reason and owner |
| --- | --- | --- |
| Replace the byte adapter with record-valued instance callbacks. | `Remove`. | The package seam keeps the binary adapter. A second provider layer adds unproved token and fault boundaries. |
| Make one persistence provider mandatory for every Agent in an instance. | `Remove`. | Instance defaults and per-Agent override or disablement are supported. |
| Add a public `Jido.Persistence.Record` now. | `Defer`. | A private versioned record is sufficient until public value need and migration are proved. |
| Add opaque `storage_version` and write `operation_id` fields. | `Remove from core target`. | Exact expected bytes and state revision are the implemented CAS contract. Reconciliation services can own retry identity. |
| Store `:active`, `:hibernated`, and `:deleted` in one lifecycle record. | `Replace`. | Use active and compact tombstone records. Hibernate is process state. |
| Keep only active records and blind delete. | `Replace`. | Tombstones preserve the stale-writer barrier. |
| Keep `get`, `put`, CAS, and `delete` as required runtime callbacks forever. | `Change in stages`. | Require get and CAS; retain put and delete as maintenance compatibility APIs first. |
| Treat every returned CAS error except explicit indeterminate as confirmed no-write. | `Replace`. | Only conflict and documented preflight rejection confirm no write. |
| Let conflict follow Agent error policy and continue. | `Conflict`. | The pending Overview and commit target remove write authority after every required write failure. |
| Stop after every persistence write error. | `Retain target, blocked`. | Seams 06, 08, and 12 must align current caller and restart behavior. |
| Add a persistence callback timeout now. | `Defer`. | No option or implementation exists. Seam 08 must define task and stop behavior first. |
| Write revision zero only after the first Turn. | `Replace`. | Target creation confirms revision zero before readiness. |
| Start Plugin runtimes only after initial persistence. | `Replace`. | Target starts them provisionally, waits for readiness, writes, then publishes. Failed write must clean them up. |
| Allow `restore: false` to ignore an existing record. | `Replace`. | It uses supplied state but must still create only when storage is absent. |
| Let delete of a missing identity return only `:ok`. | `Replace`. | Target creates a revision-zero tombstone to fence delayed creators. |
| Physically purge tombstones through the normal adapter contract. | `Remove`. | Retention and purge are provider maintenance policy. |
| Permit normal reactivation after tombstone. | `Remove`. | Reactivation requires purge and proof that old writers cannot run; a new Ref is safer. |
| Make module and instance names permanent durable identity. | `Change in stages`. | Target Ref excludes code and runtime names, but legacy keys need safe migration. |
| Change to Ref keys without mixed-version rules. | `Reject`. | Collision, dual-read, rewrite, rollback, and old-reader behavior are release gates. |
| Require positive definition revision before all persistence work. | `Defer to staged Agent contract`. | Direct and behavior-only Agents can remain unversioned during compatibility. |
| Reject every old outer record format. | `Replace`. | Legacy format 1 stays readable during a versioned migration. |
| Add an outer record migration callback. | `Defer`. | Offline or dual-read conversion is enough until an online hook has a proved need and safety model. |
| Replace plain-map Agent checkpoints with a fixed public checkpoint struct. | `Remove`. | Seam 01 keeps plain maps and complete custom callbacks. |
| Apply Plugin slice conversion inside complete custom checkpoints. | `Reject for first stage`. | Custom callbacks own the complete format and bypass Plugin conversion. |
| Add pure Plugin-owned slice dump and load. | `Retain as deferred target`. | It stays bounded and cannot see adapter, key, revision, or write result. |
| Add Plugin hooks around load, write, delete, or commit. | `Reject`. | Such hooks could change commit order or hide uncertain writes. |
| Add a general record codec for encryption or compression. | `Defer`. | Format ID, key rotation, limits, and CAS evidence need a separate design. |
| Add Ecto and Bedrock directly to core now. | `Defer placement`. | Package ownership and optional-dependency release gates are not approved. |
| Reuse V2 Ecto, Bedrock, or Redis records. | `Reject`. | V2 data needs explicit offline application conversion. |
| Keep Redis client-neutral and require EVAL for CAS. | `Retain`. | This matches current code and tests. |
| Claim Redis failover from controlled command tests. | `Reject`. | No real Redis recovery test exists. |
| Claim File power-loss durability from atomic rename. | `Reject`. | Current code has no file or directory sync proof. |
| Claim shared multi-BEAM File ownership. | `Reject`. | Current lock is one-BEAM only. |
| Add Agent discovery scans to the byte adapter. | `Reject`. | Persistence restores known identities. Catalogs and recovery control are external capabilities. |
| Add Topology callbacks or a multi-key transaction to the adapter. | `Reject`. | Current recovery composes independent Agent records and rebuilds runtime resources. |
| Claim complete durable Topology desired state. | `Reject for current scope`. | Tests restore supplied known members only. Topology desired-state ownership is separate. |
| Persist Buses, subscriptions, PIDs, timers, and ownership bindings. | `Reject`. | Runtime topology reconstructs these values after restore. |
| Treat persistence as a Directive outbox or Thread journal. | `Reject`. | Ordinary Directives are transient. Durable capability work stores explicit intent in owned Agent state. |
| Add Ecto with one new v3 table and atomic SQL CAS. | `Preserve as deferred provider input`. | SQLite and PostgreSQL tests, optional dependency, migration helper, and host Repo ownership remain required if approved. |
| Add Bedrock with transactional CAS and size preflight. | `Preserve as deferred provider input`. | A future adapter must keep host Repo ownership and prove 16 KiB key and 128 KiB value limits against the selected version. |

## High-level work sequence

This sequence defines outcomes and gates. It is not a formal implementation
plan. Create that plan only after the user approves this seam.

### Phase 0 — Resolve decisions and prerequisite blockers

- Requirements: all `PERS-REQ` identifiers.
- Required outcome: approved boundary, lifecycle, authority, identity,
  serialization, custom-checkpoint, and provider decisions.
- Compatibility: no runtime or stored-data change.
- Verification: review all `PERS-DEC` items and blocker resolutions.
- Exit criteria: one non-conflicting target exists across seams 01, 03, 05, 06,
  08, 09, and 12.

### Phase 1 — Freeze byte and error contracts

- Requirements: `PERS-REQ-001` to `PERS-REQ-022`.
- Required outcome: minimum runtime adapter, closed CAS results, normalized
  errors, and one write-authority rule.
- Compatibility: retain current built-in modules and maintenance operations.
- Verification: shared adapter conformance and live write-result matrix.
- Exit criteria: every invoked CAS result has one storage, public error,
  authority, and retry meaning.

### Phase 2 — Establish safe record lifecycle

- Requirements: `PERS-REQ-023` to `PERS-REQ-036`, `PERS-REQ-045` to
  `PERS-REQ-048`.
- Required outcome: revision-zero creation, active restore, confirmed commit,
  compact tombstone deletion, and provisional runtime cleanup.
- Compatibility: keep current hibernate and thaw entries; add no durable
  hibernated status.
- Verification: create, restore-policy, conflict, indeterminate, cleanup,
  delete-race, delayed-writer, hibernate, and stop tests.
- Exit criteria: every lifecycle path has one durable value and readiness rule.

### Phase 3 — Align serialization and migration

- Requirements: `PERS-REQ-037` to `PERS-REQ-044`.
- Required outcome: versioned outer records, safe legacy reads, Ref-key
  collision controls, custom-checkpoint compatibility, and bounded Plugin
  conversion if approved.
- Compatibility: no format-1 record becomes unreachable. Older code must not
  silently ignore a new tombstone during rollback.
- Verification: fixed binary fixtures, corrupt data, definition mismatch,
  legacy/new key collisions, rollback, custom callback, and Plugin slice tests.
- Exit criteria: every supported record and checkpoint version has an explicit
  read, write, rejection, and rollback rule.

### Phase 4 — Prove recovery boundaries

- Requirements: `PERS-REQ-049` to `PERS-REQ-051`.
- Required outcome: known-Agent restore rebuilds runtime resources without
  adding discovery, cluster ownership, or multi-record claims.
- Compatibility: static supplied Topology behavior remains supported.
- Verification: Agent and Topology restart cases on each claimed durable
  adapter, including isolated member conflict and tombstone behavior.
- Exit criteria: documentation claims no more durability than executable
  backend and lifecycle evidence proves.

### Phase 5 — Decide and qualify production providers

- Requirements: applicable `PERS-REQ-002` to `PERS-REQ-005`,
  `PERS-REQ-012` to `PERS-REQ-020`, and `PERS-REQ-045` to `PERS-REQ-051`.
- Required outcome: each retained or new provider has an owner, optional
  dependency rule, conformance result, recovery claim, and documented limit.
- Compatibility: V2 data uses explicit offline conversion. Current v3 Redis
  key and value behavior remains readable during any core format migration.
- Verification: package-without-optionals fixture plus real backend jobs for
  every durability claim.
- Exit criteria: no adapter is listed as supported beyond its passing evidence.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `PERS-REQ-001`, `PERS-REQ-002` | Persistence and adapter module docs and code | Preserve owner split through record migration. | `Proven` |
| `PERS-REQ-003` to `PERS-REQ-005` | Four callbacks are required; host ownership is documented | Two-required-callback conformance plus maintenance compatibility tests. | `Partial` |
| `PERS-REQ-006`, `PERS-REQ-007` | `lib/jido/persistence.ex:79-98,284-315` | Default and custom checkpoint ordering on each retained adapter. | `Proven` |
| `PERS-REQ-008`, `PERS-REQ-009` | Current active envelope has copied identity and revision; no tombstone | Ref, definition-revision, active, and tombstone fixtures. | `Missing` |
| `PERS-REQ-010` | PID and improper-list tests; current validator allows non-byte-aligned bitstrings | Complete prohibited-term matrix with bounded paths. | `Partial` |
| `PERS-REQ-011` to `PERS-REQ-016` | Revision and concurrent-writer tests | Map Server revision proof directly to the closed adapter suite. | `Proven` for current active records |
| `PERS-REQ-017` | Adapter option tests | Approved seam-12 invalid-options code. | `Partial` |
| `PERS-REQ-018` | ETS, File, Redis, and live conflict tests | Shared conflict/no-write cases for every adapter. | `Proven` for current adapters |
| `PERS-REQ-019` | No adapter uses a typed preflight rejection | Rejection before backend work and no-write proof. | `Missing` |
| `PERS-REQ-020` | Redis and lost-reply tests cover several cases | Returned plain error, raise, throw, exit, invalid result, and timeout matrix. | `Partial` |
| `PERS-REQ-021` | Public Persistence returns raw terms and `ExecutionError` | Public `PersistenceError` code tests. | `Conflict` |
| `PERS-REQ-022` | Indeterminate stop passes; conflict continuation passes | Every required write failure removes authority before next evaluation. | `Conflict` |
| `PERS-REQ-023` to `PERS-REQ-028` | Startup returns before any initial write | Revision-zero storage, all restore policies, failure publication, and Plugin cleanup. | `Missing` |
| `PERS-REQ-029`, `PERS-REQ-030` | Invalid record and identity tests | Preserve with new active record and Ref. | `Proven` for current record |
| `PERS-REQ-031` | Definition-revision target test is skipped | Stored revision match, mismatch, missing-old-record, and rollback cases. | `Blocked` |
| `PERS-REQ-032` to `PERS-REQ-036` | Blind delete and skipped delayed-writer case | Tombstone load, missing delete, race, stale writer, purge, and reactivation tests. | `Missing` |
| `PERS-REQ-037`, `PERS-REQ-038` | Safe decode and corrupt-record tests | All invalid fields, unknown kinds and versions, and no-write assertions. | `Partial` |
| `PERS-REQ-039` | Current format-1 load tests | Fixed legacy binary fixture under the new reader. | `Proven` for current reader; migration is `Partial` |
| `PERS-REQ-040`, `PERS-REQ-041` | No core Ref or migration path | Collision, dual-read, rewrite, rollback, and removal-gate tests. | `Blocked` |
| `PERS-REQ-042` | Custom callback tests in `test/jido/agent_test.exs:937-1010` | Run one complete custom pair through each retained adapter and new record format. | `Partial` |
| `PERS-REQ-043`, `PERS-REQ-044` | No Plugin Persistence facet | Bypass, slice isolation, portability, schema, and no-runtime tests. | `Deferred` |
| `PERS-REQ-045` | Automatic restore and thaw tests | Preserve for Ref and active/tombstone records. | `Proven` for current active record |
| `PERS-REQ-046`, `PERS-REQ-047` | Commit and indeterminate-write tests | Full closed write-result matrix. | `Proven` for covered current results |
| `PERS-REQ-048` | Hibernate and clean-stop code keep active maps | Explicit no-liveness-field fixture. | `Proven` for current record |
| `PERS-REQ-049` | Plugin and Topology restart tests | All runtime handle exclusions and rebuild causes. | `Partial` |
| `PERS-REQ-050` | ETS Topology member recovery tests | Each claimed durable adapter, member tombstone, and isolated conflict. | `Partial` |
| `PERS-REQ-051` | No such adapter APIs exist | Public boundary inventory and external capability fixture. | `Proven` for current API |

## Migration and compatibility

- Keep current `Jido.Persistence` direct functions, instance defaults,
  per-Agent override or disablement, IDs, PIDs, term partitions, hibernate,
  thaw, ETS, File, Redis, and complete custom Agent callbacks.
- Introduce the minimum adapter behavior without removing built-in maintenance
  functions in the same step. A later deprecation needs public usage evidence.
- Keep fixed legacy format-1 and checkpoint-version-1 fixtures. Add a new outer
  format only with an older-reader rejection and rollback rule.
- Do not move to Ref keys before stable namespace binding and term-partition
  conversion exist. Detect legacy/new collisions before the first new write.
- Do not overwrite legacy records in place during a rolling deployment unless
  all writers and rollback readers understand the new tombstone and key rules.
- Keep V2 Ecto, Bedrock, and Redis data offline. Stop V2 writers, export with V2
  code, convert application and Plugin state, and save through the V3 API.
- Keep the current v3 Redis client-neutral option model. Document that TTL also
  limits any future tombstone barrier.
- State File guarantees narrowly: atomic rename and one-BEAM serialization are
  proved; power-loss sync is not.
- If Ecto is approved, keep its dependency and database driver optional, use a
  new V3 table, and prove atomic SQL CAS for each named database.
- If Bedrock is approved, keep the host Repo external, reject key and value
  limits before a transaction, and prove restart behavior with the selected
  Bedrock version.
- Rollback must restore adapter result handling, Server authority behavior, and
  caller errors as one compatible unit.

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `PERS-BLK-001` | `Blocker` | 00 Overview | Initial records, all-error authority loss, and tombstones are pending. | Approve or change the Overview durability decision. |
| `PERS-BLK-002` | `Blocker` | 90 Package boundaries | Production provider placement and public compatibility are pending. | Approve provider ownership and migration gates. |
| `PERS-BLK-003` | `Blocker` | 12 Errors and contracts | `PersistenceError`, codes, controls, and portable paths are pending. | Approve the public result contract. |
| `PERS-BLK-004` | `Blocker` | 01 Agent and 02 Agent authoring | Definition revision and default checkpoint evolution are pending. | Approve version and old-checkpoint rules. |
| `PERS-BLK-005` | `Blocker` | 03 Agent identity and 09 Jido instance | Ref exists only as a target, and namespace binding is undefined. | Approve Ref, namespace, and partition conversion. |
| `PERS-BLK-006` | `Blocker` | 06 Commit and effects and 08 Agent Server | Current conflict continuation disagrees with all-error authority loss. | Select one rule and define stop, reload, and caller behavior. |
| `PERS-BLK-007` | `Blocker` | 07 Persistence | Tombstone retention, purge authorization, same-identity reactivation, TTL, and rollback are not approved. | Approve the lifecycle maintenance rules. |
| `PERS-BLK-008` | `Blocker` | 05 Plugins and 01 Agent | Complete custom checkpoints and Plugin slice conversion have no long-term composition. | Approve first-stage bypass and later composition or permanent deferral. |
| `PERS-BLK-009` | `Assumption` | 08 Agent Server | Plugin runtimes can start provisionally and be cleaned up before publication. | Prove all startup failure paths. |
| `PERS-BLK-010` | `Assumption` | 10 Runtime topology | Persistence restores known identity only and does not own discovery or placement. | Keep later topology contracts separate. |
| `PERS-BLK-011` | `Blocker` | Adapter owners and 99 Delivery | There is no shared conformance suite or real backend recovery matrix. | Pass the suite before a provider claim. |
| `PERS-BLK-012` | `Blocker` | Design index owner | `docs/design/README.md` still lists the removed legacy persistence files. | Update the index in a separately authorized edit. |

## Completion criteria

- [ ] The user has approved or changed every `PERS-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `PERS-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains.
- [ ] Initial creation, active restore, commit, hibernate, tombstone, purge, and
      reactivation have one documented record and authority result.
- [ ] Every adapter passes the shared CAS conformance set.
- [ ] Legacy and new record and key formats have collision, rollback, and
      old-reader evidence.
- [ ] Complete custom checkpoints and any Plugin slice conversion have an
      approved composition and tests.
- [ ] Backend documentation states only proved durability and size limits.
- [ ] Dependent seams use the approved contract.
- [ ] A separate formal implementation plan is created only after approval.
