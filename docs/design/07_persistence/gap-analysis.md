# Persistence seam gap analysis

> This report describes the code on branch `v3-spike` on 2026-09-08. Runtime
> code under `lib` is the source of truth. Design proposals are not implemented
> facts.

## Scope and owner

This review covers only the persistence seam. It covers persistence records,
the byte-adapter contract, compare-and-swap (CAS), the first durable write,
tombstones, migrations, and backend adapters. It also covers the narrow
interfaces from Agent checkpoint and restore, Agent Server commit and startup,
Plugin-owned state, Jido instance configuration, errors, and Topology member
recovery.

Current owner: `Jido.Persistence` owns record keys, record encoding, record
validation, checkpoint calls, restore calls, and adapter fault containment.
`Jido.Persistence.Adapter` and each backend own binary storage operations. The
host application owns any storage process. This ownership is stated in the
public module documentation and is present in the code
(`lib/jido/persistence.ex:2-15`, `lib/jido/persistence/adapter.ex:2-7`).

The two seam documents have different target boundaries:

- `instance-persistence.md` proposes instance callbacks that exchange a public
  `Jido.Persistence.Record` with an opaque `storage_version`
  (`docs/design/07_persistence/instance-persistence.md:16-43,62-118`).
- `persistence-adapters.md` says to keep the current binary byte-store boundary
  and reduce it to `get/2` and `compare_and_swap/4`
  (`docs/design/07_persistence/persistence-adapters.md:14-41,127-178`).

This boundary choice is not resolved. It must be resolved before implementation.

## Implemented baseline

These statements are current facts.

### Record and identity

`Jido.Persistence` stores an encoded map. It is not a public struct. Its fields
are `format`, `kind`, `instance`, `agent_module`, `agent_id`, `partition`,
`revision`, and `checkpoint` (`lib/jido/persistence.ex:284-320`). The only valid
record kind is `:agent`, and the only valid outer format is `1`
(`lib/jido/persistence.ex:330-363`).

The key is a binary encoding of `{instance_module, agent_module, partition,
agent_id}` with the prefix `jido:agent:v1:`
(`lib/jido/persistence.ex:22-23,153-160`). Thus, the local Jido module and Agent
module are part of durable identity. There is no implemented `Jido.Agent.Ref`,
`Jido.Persistence.Record`, `Jido.Agent.Commit`, operation ID, lifecycle status,
or opaque storage-version token.

The default Agent checkpoint stores checkpoint format version `1`, Agent module,
ID, a complete Agent definition, and complete Agent state
(`lib/jido/agent.ex:403-423`). Load validates the outer identity and validates
the restored Agent module and ID (`lib/jido/persistence.ex:119-134,330-371`).
Both save and load reject non-portable records
(`lib/jido/persistence.ex:296-315,351-358`).

### CAS and write authority

Save first reads the current bytes, validates the current record and revision,
encodes the proposed record, and calls adapter CAS with the exact bytes that it
read (`lib/jido/persistence.ex:79-98,248-282`). A Server supplies its current
state version as `expected_revision` (`lib/jido/agent_server.ex:2915-2929`). A
successful Turn writes the next revision before it changes live state or sends
the reply and Directives (`lib/jido/agent_server.ex:1493-1545`).

The current adapter contract requires `get/2`, `put/3`,
`compare_and_swap/4`, and `delete/2`. Only `validate_options/1` is optional
(`lib/jido/persistence/adapter.ex:14-46`). Adapter validation enforces all four
storage functions (`lib/jido/persistence.ex:200-214`).

The Server stops after `:indeterminate`, `{:indeterminate, reason}`, or a
contained CAS exception or invalid CAS result. A plain returned error, including
`:conflict`, goes to the configured Agent error policy and can let the Server
continue (`lib/jido/agent_server.ex:1548-1594`). The current test explicitly
keeps a stale Server alive after a conflict
(`test/jido/persistence_test.exs:305-357`). Hibernate also returns a write error
and keeps the Server alive (`lib/jido/agent_server.ex:623-630`;
`test/jido/persistence_test.exs:208-232`).

### Startup, restore, hibernate, and delete

Startup restores a stored record when policy is `:if_found` or `:required`.
When `:if_found` finds no record, or when restore is `false`, startup uses the
supplied Agent at the supplied state version (`lib/jido/agent_server.ex:2874-2905`).
It then starts Plugin runtimes, waits for readiness, and reports startup success
without a revision-zero persistence write
(`lib/jido/agent_server.ex:438-533`). The first durable write occurs on a
successful Turn, hibernate, or clean stop
(`lib/jido/agent_server.ex:1493-1507,623-630,2932-2950`).

Hibernate saves the same active Agent record and stops on success. It does not
write a hibernated lifecycle state. `Jido.Persistence.delete_agent/4` calls the
adapter's blind delete operation. Load then returns `:not_found`
(`lib/jido/persistence.ex:137-150`;
`test/jido/persistence_test.exs:395-404`). No tombstone is written.

### Backends and migration surface

Three adapters exist:

- ETS uses atomic `insert_new` and `select_replace`. Its data ends with the
  BEAM. Its on-demand public table can transfer to `Jido.Supervisor`
  (`lib/jido/persistence/ets.ex:1-7,45-59,77-113`).
- File uses an in-BEAM `:global` lock and atomic rename. One BEAM must own the
  directory (`lib/jido/persistence/file.ex:1-12,44-77,86-103`).
- Redis uses an application-supplied command function. CAS is one Lua `EVAL`.
  Redis errors and invalid replies from CAS become indeterminate. Optional TTL
  applies to every stored value (`lib/jido/persistence/redis.ex:1-10,84-120`).

There is no Ecto adapter, Bedrock adapter, Ecto migration helper, or optional
Ecto or Bedrock dependency. The package dependency list confirms this
(`mix.exs:351-375`). Public ExDoc groups only ETS, File, and Redis
(`mix.exs:263-269`).

The outer record has no migration callback. The default Agent restore accepts
only checkpoint format version `1`, but an Agent can replace `checkpoint/2` and
`restore/2` to own a custom format (`lib/jido/agent.ex:128-132,370-400,521-575`).
There is no Plugin callback for the durable encoding or migration of only its
state slice (`lib/jido/plugin.ex:67-102`). Public guidance requires explicit
offline conversion of V2 data and states that there is no automatic conversion
(`guides/storage.md:25-27`).

## Aligned contracts

These current contracts agree with the design direction.

1. Core owns record meaning and validation. Adapters store bytes only.
2. Live commit uses an exact-byte atomic CAS. Live state and post-commit
   Directives change only after confirmed storage success.
3. The Server uses its current state revision to detect stale writes.
4. CAS conflicts do not replace stored bytes. ETS and File concurrency tests
   show one winner for one expected value
   (`test/jido/persistence/ets_test.exs:17-52`,
   `test/jido/persistence/file_test.exs:18-49`).
5. A CAS exception or an explicit indeterminate result stops a Turn writer
   before another Action runs
   (`test/jido/persistence/indeterminate_write_test.exs:46-94`).
6. Record envelope identity, restored identity, and nested portable terms are
   validated (`test/jido/persistence/checkpoint_identity_test.exs:14-32`,
   `test/jido/persistence/checkpoint_portability_test.exs:15-49`).
7. Instance defaults can be replaced or disabled for one Agent
   (`lib/jido/agent_server/options.ex:377-390`).
8. The host owns File, Redis, and future database processes. Jido does not start
   them.
9. Current Topology tests show that ETS-backed member Agent state can restore and
   Bus resources can rebuild when the application supplies the same Topology
   again (`test/jido/topology/controller_test.exs:247-284`,
   `test/jido/topology/controller/composition_runtime_test.exs:222-245`).

## Gaps

### Missing implementation

These items are proposals, not current facts.

1. **Public record model.** The proposed `Jido.Persistence.Record`, Agent
   `Commit`, Agent `Ref`, lifecycle status, `operation_id`, and bounded opaque
   `storage_version` do not exist. Current code uses a private map and an integer
   revision.
2. **Ref-based durable identity.** Current keys contain the Jido instance module
   and Agent module. They do not use the proposed stable
   `{namespace, partition, id}` identity.
3. **Initial durability.** A new persistent Agent can report ready with no stored
   revision-zero record. Supplied initial state can be lost on VM failure.
   `restore: false` also does not read storage before readiness. Thus it cannot
   prove that the identity is absent.
4. **Durable lifecycle state.** Hibernate has no stored `:hibernated` status.
   Normal deletion has no `:deleted` tombstone. A delayed revision-zero writer
   can recreate a deleted identity. The acceptance test for this case remains
   skipped (`test/examples/99_research/99_13_durable_delete/durable_delete_test.exs:21-30`).
5. **Strict write-authority loss.** A conflict or another plain CAS error can
   leave the Server active. The instance proposal requires every persistence
   write error to remove write authority
   (`docs/design/07_persistence/instance-persistence.md:135-142,208-217`).
6. **Refined adapter surface.** Raw `put/3` and `delete/2` are still required.
   Core still validates them, and delete still uses blind removal.
7. **Strict CAS result set.** There is no `{:rejected, reason}` preflight result.
   Core propagates any `{:error, reason}`. It does not classify every unknown
   returned CAS error as indeterminate.
8. **Persistence timeout.** There is no instance `persistence_timeout` option,
   bounded persistence task, or timeout-to-indeterminate rule.
9. **Definition revision.** The checkpoint and load path do not store or enforce
   a positive module-owned definition revision. Compatible definition changes
   can restore with the current module definition. The focused research test for
   a revision mismatch remains skipped
   (`test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:19-28`).
10. **Plugin state codec.** `checkpoint_state/3` and `restore_state/3` do not
    exist. A reusable Plugin cannot own migration of only its durable state
    slice.
11. **Ecto and Bedrock.** Both adapters, their optional dependencies, migrations,
    backend limit checks, and backend integration tests are absent.
12. **Logical instance delete API.** The proposed Ref-based
    `MyApp.Jido.delete_agent/1` does not exist. The current public instance API
    stops live processes but exposes storage deletion only through
    `Jido.Persistence.delete_agent/4` (`lib/jido.ex:487-528`).

### Design/code conflict

1. `instance-persistence.md` proposes record-valued instance callbacks and an
   opaque storage token. `persistence-adapters.md` says that no new high-level
   provider contract is needed and keeps exact-byte CAS. Both cannot be the one
   core persistence boundary without a defined layering model.
2. `instance-persistence.md` proposes one public Record with status
   `:active | :hibernated | :deleted` and a nested Commit. The adapter design
   proposes a smaller `:agent_tombstone` map that does not retain Agent state and
   says that it does not add a full lifecycle status model
   (`docs/design/07_persistence/persistence-adapters.md:180-215`). The tombstone
   shape and load result also differ: one proposal uses Record status, while the
   other uses record kind and `{:error, :deleted}`.
3. The instance proposal requires every write error to stop the Server. Current
   public Agent Server documentation says a conflict follows the configurable
   error policy, and only uncertain errors always stop the Server
   (`lib/jido/agent_server.ex:172-178`). The implementation and tests follow the
   public documentation, not the proposal.
4. The current adapter module documentation says that returned CAS errors other
   than indeterminate confirm that no write occurred
   (`lib/jido/persistence/adapter.ex:31-35`). The adapter design limits confirmed
   no-write errors to `:conflict` and `{:rejected, reason}` and treats all other
   results as uncertain
   (`docs/design/07_persistence/persistence-adapters.md:161-175`).
5. The instance proposal requires definition revision enforcement as part of
   create and activation. The adapter design explicitly defers stable identity,
   definition revision enforcement, and live state migration
   (`docs/design/07_persistence/persistence-adapters.md:260-270,795-813`).
6. The seam index says persistence owns durable lifecycle state and deletion
   (`docs/design/07_persistence/README.md:5-6`), but current code owns only active
   checkpoint records and physical deletion.

### Missing decision

1. Select the public boundary: exact-byte adapters only, instance Record
   callbacks only, or a defined two-layer model. If two layers are kept, define
   which layer owns validation, encoding, timeout, retry identity, and CAS
   tokens.
2. Select one durable record algebra. Decide whether active, hibernated, and
   deleted values share one public Record or use separate active and tombstone
   kinds. Define what a load of each value returns.
3. Decide if all write errors remove Server authority, or only uncertain errors.
   Also decide if a confirmed conflict can use Agent error policy. The current
   documents specify both policies.
4. Decide whether stable namespace and definition revisions are release
   prerequisites for persistence. A change from module-based keys to Ref-based
   keys requires data migration and can change identity across deployments.
5. Define the outer record evolution rule. Current format `1` rejects another
   format. State whether core supports multiple read formats, an outer migration
   hook, or offline conversion only.
6. Define the Plugin migration rule. State whether the proposed Plugin callback
   pair is part of the first persistence release or deferred to Agent-owned
   custom checkpoint code.
7. Define create semantics for `restore: false`. The design says it must create
   only when storage is absent. State whether any existing active record,
   tombstone, or same-revision record makes startup fail.
8. Define hibernate and clean-stop semantics. State whether clean stop keeps an
   active record, writes a hibernated record, or uses another lifecycle state.
9. Define durability claims for each backend. In particular, specify File sync
   and crash guarantees, Redis TTL effects on active records and tombstones, and
   Bedrock size rejection before a transaction.

### Missing verification

1. There is no shared adapter conformance suite under `test/support`. ETS, File,
   and Redis have separate tests with different coverage.
2. There is no test that proves a revision-zero record exists before startup
   returns, or that an initial write conflict or indeterminate result prevents
   readiness and cleans up Plugin runtimes.
3. The durable-delete fencing test is skipped. There are no tombstone load,
   concurrent delete, TTL-retention, or delayed-writer tests.
4. The current Redis suite uses a controlled command function. It verifies Lua
   command shape and result mapping but not a real Redis process, failover, or
   restart (`test/jido/persistence/redis_test.exs:63-89,138-147`).
5. There are no Ecto SQLite or PostgreSQL migration and CAS tests, no Bedrock
   fake or real-restart tests, and no package test without optional dependencies.
6. Custom Agent checkpoint behavior is tested mainly at the core callback
   boundary. There is no shared test that runs one custom checkpoint and restore
   pair on every real adapter.
7. Plugin slice migration and validation tests cannot exist until the Plugin
   callback contract exists. The current state-migration example covers an
   explicit live Agent command. It does not prove Plugin-owned restore migration
   or live definition migration
   (`test/examples/99_research/99_15_state_migration/state_migration_test.exs:8-59`).
8. Topology recovery tests use ETS only. They do not cover all durable adapters,
   tombstoned members, or isolation of one member conflict.
9. There is no persistence callback timeout test because there is no timeout
   implementation.

## Narrow dependency notes

- **Agent and commit seam:** Persistence depends on `Agent.checkpoint/2` and
  `Agent.restore/3`. The Server supplies integer state revisions and enforces
  write-before-live-state ordering. A future `Jido.Agent.Commit` must not change
  this order or add a general Directive outbox
  (`docs/design/06_commit-and-effects/commit-and-effects.md:11-23,89-103`).
- **Identity and Jido instance seams:** Ref-based records depend on a stable
  instance namespace and `Jido.Agent.Ref`. Neither is implemented. Current
  `use Jido` exposes an adapter through `__jido_persistence__/0`, not record
  callbacks (`lib/jido.ex:94-107`).
- **Plugin seam:** Current checkpoints include Plugin-owned state because it is
  part of complete Agent state. The proposed Plugin codec must remain pure and
  limited to one owned state key. It must not get the adapter or write result.
- **Error seam:** Current persistence returns raw control atoms and general
  `ExecutionError` values. The proposed `Jido.Error.PersistenceError`, stable
  codes, and timeout normalization are not implemented. The persistence design
  must align with the error design before public result types change
  (`docs/design/12_errors-and-contracts/errors.md:37-59,155-169`).
- **Topology seam:** Current evidence supports composition over per-Agent
  persistence only. It does not support a durable Topology target or a
  multi-record atomic commit.
- **Package boundary:** Ecto, Bedrock, Redis clients, and database drivers must
  remain optional host-owned dependencies. Core adapters must not start their
  processes.

## Ordered recommendations

These are proposals. They do not describe current behavior.

1. Resolve the record boundary first. Prefer one small binary adapter contract
   in core. Add a public Record layer only if the instance API needs a stable
   application callback boundary. If both exist, document the conversion and
   fault boundary between them.
2. Freeze one record algebra and one identity model before backend work. Include
   active and deleted values, revision or storage token semantics, namespace,
   definition revision, and format evolution.
3. Freeze the write-result policy. Use a closed CAS result set. Make every
   unknown result indeterminate. Decide and document whether confirmed conflicts
   also remove live Server authority.
4. Implement revision-zero create before readiness. Make startup report whether
   it loaded or prepared a new Agent. Use create-only CAS for every new Agent,
   including `restore: false`, and clean up provisional Plugin runtimes on every
   failed result.
5. Replace normal blind delete with CAS tombstones. Keep physical purge outside
   the runtime adapter. Enable the delayed-writer acceptance test.
6. Add persistence timeout handling and the selected write-authority shutdown
   rule. Align public errors and Agent Server documentation with that rule.
7. Add the shared conformance suite. Run it first for ETS, File, and Redis. Add
   startup, tombstone, timeout, and custom-checkpoint lifecycle tests.
8. Decide the migration layers. Keep V2 conversion offline. Add an explicit
   outer-record evolution rule, definition revision enforcement, and either the
   Plugin state codec pair or a clear deferral statement.
9. Add Ecto after the contract is stable. Use one new table, optional Ecto SQL,
   versioned migrations, and atomic expected-byte update tests for SQLite and
   PostgreSQL.
10. Add Bedrock after the same suite is stable. Validate host Repo functions,
    reject oversize key or value data before a transaction, and test a real
    single-node restart.
11. Run the Topology member-recovery compatibility cases on each durable adapter.
    Keep the claim limited to per-Agent state and rebuilt runtime resources.
12. Update all public module and guide text only after behavior and tests agree.
    Do not describe Record structs, tombstones, first-write durability, Ecto,
    Bedrock, or automatic migration as implemented before that point.

## Evidence references

Primary implementation evidence:

- `lib/jido/persistence.ex:1-16,59-150,153-160,200-282,284-430`
- `lib/jido/persistence/adapter.ex:1-46`
- `lib/jido/persistence/ets.ex:1-113`
- `lib/jido/persistence/file.ex:1-103`
- `lib/jido/persistence/redis.ex:1-128`
- `lib/jido/agent_server.ex:438-533,623-630,1493-1594,2874-2950`
- `lib/jido/agent.ex:128-132,370-423,521-575`
- `lib/jido/plugin.ex:67-102`
- `lib/jido.ex:94-107,473-528,631-684`
- `mix.exs:263-269,351-375`

Primary design evidence:

- `docs/design/07_persistence/README.md:3-24`
- `docs/design/07_persistence/instance-persistence.md:16-43,45-142,144-285`
- `docs/design/07_persistence/persistence-adapters.md:14-59,127-270,272-404,406-618,620-813`

Focused verification evidence:

- `test/jido/persistence_test.exs:259-279,305-357,384-505`
- `test/jido/persistence/adapter_test.exs:59-110`
- `test/jido/persistence/indeterminate_write_test.exs:35-115`
- `test/jido/persistence/checkpoint_identity_test.exs:14-32`
- `test/jido/persistence/checkpoint_portability_test.exs:15-49`
- `test/jido/persistence/ets_test.exs:17-52`
- `test/jido/persistence/file_test.exs:18-49`
- `test/jido/persistence/redis_test.exs:63-89,138-147`
- `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs:13-30`
- `test/examples/99_research/99_15_state_migration/state_migration_test.exs:8-59`

Focused test run: `mix test test/jido/persistence_test.exs
test/jido/persistence --include research --seed 0` completed with 56 passing
tests. Skipped example acceptance tests were not part of this command.
