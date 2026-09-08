# Persistence adapters and durable lifecycle

> Supporting persistence design. This document is pending approval.

## Goal

Make durable Agent persistence a complete Jido core feature. Add optional Ecto
and Bedrock adapters. Keep Redis support. Keep the core storage contract small,
explicit, and easy to replace.

This work must not restore the v2 `Jido.Storage` and `Jido.Persist` design. Jido
v3 stores one complete Agent checkpoint. It does not own a Thread journal.

## Decision summary

1. Keep `Jido.Persistence` as the one owner of keys, record encoding, identity
   checks, revision checks, checkpoint calls, restore calls, and fault handling.
2. Keep adapters as byte stores. Do not let Ecto, Bedrock, or Redis decode a
   Jido Agent record.
3. Reduce the required adapter contract to `get/2` and
   `compare_and_swap/4`. Keep `validate_options/1` optional.
4. Remove unconditional `put/3` and blind `delete/2` from the required adapter
   contract. Core does not need them for Agent commits.
5. Change Agent deletion to a compare-and-swap tombstone write. Physical purge
   is a backend maintenance task.
6. Save a new persistent Agent at revision zero before it becomes ready. A
   configured durable Agent must not first become durable only after its first
   Turn.
7. Add `Jido.Persistence.Ecto` and `Jido.Persistence.Bedrock` to core. Keep
   `Jido.Persistence.Redis` in core with its client-neutral `:command_fn` API.
8. Use optional Mix dependencies. Installing Jido alone must not install Ecto,
   a database driver, or Bedrock.
9. Keep adapter selection explicit. Do not select an adapter because a package
   is present.
10. Keep storage process ownership in the host application. Jido must not start
    an Ecto Repo, a Bedrock cluster, or a Redis client.
11. Do not add general Plugin hooks around load, write, delete, or commit.
12. Add an optional pure callback pair for a Plugin to encode and restore only
    its own durable state slice.
13. Treat Topology durability as composition over Agent persistence. Do not add
    Topology-specific operations to the byte adapter.

## What exists now

The v3 branch already has the main persistence system:

- `Jido.Persistence.Adapter` defines a binary key and value contract.
- `Jido.Persistence` builds and validates the Agent record.
- Every successful Server Turn saves one higher revision.
- The Server passes the current revision as `:expected_revision`.
- The adapter must use atomic compare-and-swap.
- A conflict cannot replace stored data.
- An uncertain write stops that Server before it runs more Agent work.
- Normal start can restore stored state.
- Hibernate, thaw, instance defaults, Agent start overrides, and partitions work.
- ETS, File, and Redis adapters exist.

This is a good base. The Ecto and Bedrock work does not need a new high-level
persistence provider contract.

## Findings from v2

### `jido_ecto`

The v2 package implements `Jido.Storage`. It owns checkpoint terms, Thread
snapshots, and ordered Thread entries. It creates three tables:

- `jido_checkpoints`
- `jido_threads`
- `jido_thread_entries`

Checkpoint writes use an unconditional upsert. This does not meet the v3
compare-and-swap contract. Most of the package is for the v2 Thread model and
must not move to core.

Useful donor work is limited to these items:

- Ecto Repo and query option checks.
- A versioned migration helper.
- SQLite and PostgreSQL test setup.
- Prefix support.

Source: [agentjido/jido_ecto](https://github.com/agentjido/jido_ecto).

### `jido_bedrock`

The v2 package also implements `Jido.Storage`. It owns checkpoint envelopes,
Thread metadata, Thread entries, memory records, indexes, error modules, and
telemetry.

Only the small Bedrock transaction pattern is needed for v3 Agent persistence.
The memory and Thread code stays out of Jido core.

Useful donor work is limited to these items:

- Bedrock Repo validation.
- Prefix validation.
- Transaction rollback on an expected-value conflict.
- Real single-node restart tests.

Bedrock transactions track normal reads and retry transaction conflicts. A
Bedrock key has a 16 KiB limit. A Bedrock value has a 128 KiB limit. The core
adapter must report this value limit before it starts a write.

Sources: [agentjido/jido_bedrock](https://github.com/agentjido/jido_bedrock) and
[Bedrock.Repo](https://github.com/bedrock-kv/bedrock/blob/main/lib/bedrock/repo.ex).

### v2 Redis and current v3 Redis

The v2 Redis adapter was already part of Jido core. It used a client-neutral
`:command_fn`, an optional prefix, and an optional TTL. Keep these good parts.

Do not keep the v2 data model. It stored unconditional checkpoint terms under
`{prefix}:cp:{hash}`. It also stored complete v2 Thread journals under
`{prefix}:th:{thread_id}`. The checkpoint path had no compare-and-swap write.
The Thread path used an Erlang global lock, not a Redis atomic operation.

The current v3 Redis adapter has the correct split. Jido owns the record. The
adapter owns Redis commands and atomic byte replacement. The host application
owns the Redis client through `:command_fn`.

Retain this model. Do not add a required Redix dependency.

Source:
[Jido v2 Redis adapter](https://github.com/agentjido/jido/blob/v2.3.3/lib/jido/storage/redis.ex).

## Design pressure found in v3

### 1. The adapter contract has two operations that core does not need

`Jido.Persistence.save_agent/3` uses `get/2` and `compare_and_swap/4`. It does
not use adapter `put/3`. Raw `put/3` can also bypass record and revision checks.

`delete/2` is a blind storage delete. It removes revision history. A delayed
revision-zero writer can then create the deleted Agent again. The existing
FA-05 research test shows this result.

The minimum safe contract is:

```elixir
@type cas_failure ::
        :conflict
        | {:rejected, term()}
        | :indeterminate
        | {:indeterminate, term()}

@callback get(binary(), keyword()) ::
            {:ok, binary()} | {:error, term()}

@callback compare_and_swap(
            binary(),
            :not_found | binary(),
            binary(),
            keyword()
          ) :: :ok | {:error, cas_failure()}

@callback validate_options(keyword()) :: :ok | {:error, term()}
@optional_callbacks validate_options: 1
```

Keep the compare-and-swap result set strict:

- `:ok` means that the new value is stored.
- `{:error, :conflict}` means that the expected value did not match. No write
  occurred.
- `{:error, {:rejected, reason}}` means that validation rejected the operation
  before a write started. Bedrock size checks use this result.
- An indeterminate result means that the backend may have stored the value.
- Any exception, exit, throw, or other callback result is indeterminate.

This rule removes a current unsafe case. Today, a custom adapter can return a
plain error after a write attempt. The Server can then continue because the
core does not know that the result is uncertain. After this change, an adapter
must use `:conflict`, `:rejected`, or `:indeterminate`. Core treats every other
compare-and-swap result as an invalid and uncertain result.

Backend-specific import and purge tools can use backend APIs. They do not need
to be part of the runtime adapter contract.

### 2. Deletion needs a durable record

Change `Jido.Persistence.delete_agent/4` to write a tombstone with
compare-and-swap. The tombstone keeps only the durable identity and the last
revision. It does not keep Agent state.

```elixir
%{
  format: 1,
  kind: :agent_tombstone,
  instance: MyApp.Jido,
  agent_module: MyApp.Agent,
  agent_id: "agent-42",
  partition: nil,
  revision: 7
}
```

Rules:

- Delete reads and validates the current record.
- Delete replaces only the bytes that it read.
- A concurrent newer commit makes delete return `{:error, :conflict}`.
- Delete of a missing identity creates a revision-zero tombstone.
- Load of a tombstone returns `{:error, :deleted}`.
- Save never replaces a tombstone.
- Physical purge is not part of `Jido.Persistence`.
- A Redis TTL also limits tombstone retention. The guide must state this limit.

`delete_agent/4` now means durable retirement. A caller that wants to use the
same identity again must first prove that all old writers are stopped, and then
use a backend maintenance tool to purge the tombstone. The safer normal action
is to use a new Agent identity.

This change completes the FA-05 acceptance target. It does not add a full Agent
lifecycle status model.

### 3. A new Agent is not durable before its first Turn

Today, a configured Agent with no stored record becomes ready at revision zero.
The durable record appears after a successful Turn, hibernate, or clean stop.
This can lose supplied initial state after a VM failure.

For a persistent Agent, use this start order:

```text
load and validate a stored record
  -> use it, or prepare the supplied revision-zero Agent
  -> start Plugin runtimes and wait for readiness
  -> create the revision-zero record with compare-and-swap when it is new
  -> publish the Server as ready
  -> accept Signals
```

If the initial write conflicts, stop the provisional Plugin runtimes and fail
startup. If the write result is uncertain, fail startup and require a later
load. Do not publish the Server as ready.

`restore: :required` still requires a stored active record. `restore: :if_found`
restores or creates. `restore: false` uses supplied state but must create only
when the record is absent. It must not overwrite an existing record or a
tombstone.

### 4. Backend limits must stay adapter-specific

Do not add a capability negotiation API in this change. Ecto and Redis can
usually store values larger than Bedrock can. Bedrock must check its documented
limit and return a clear error before a transaction starts.

Applications with larger Agent state can use another adapter or a custom
adapter. A future chunked Bedrock adapter needs a separate atomic manifest
design. It must not enter this first implementation.

### 5. Discovery is not part of checkpoint storage

Do not add `list_agents/1` or recovery scans to the byte adapter. The current
contract restores a known Agent identity. Applications that need discovery can
keep an index in their domain store. Cluster activation, leases, and ownership
are separate features.

### 6. Definition revisions and stable namespace need separate work

Real durable stores make two existing research gaps more important:

- A module definition change has no required definition revision check.
- The local Jido instance module is part of the current durable identity.

Do not combine these larger identity and live-upgrade designs with the adapter
port. Keep the current checkpoint override as the migration point. Open a
separate plan for canonical Agent references, definition revisions, and live
state migration.

## Core adapter API and override order

Keep the current configuration form:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    persistence: {Jido.Persistence.Ecto, repo: MyApp.Repo}
end
```

Use this order:

1. The Jido instance supplies the default adapter.
2. `Jido.start_agent/3` can replace that adapter for one Agent.
3. The Agent start option can set `persistence: false` to disable the default.
4. Direct `Jido.Persistence` calls can take an explicit adapter tuple.
5. An application can implement `Jido.Persistence.Adapter` and replace all
   built-in adapters.
6. An Agent module can override `checkpoint/2` and `restore/2` for its durable
   data format.

Do not add global application environment lookup inside an adapter. Repo and
client configuration stays explicit in the adapter options.

## Plugin extension boundary

There is no current `Jido.Plugin` callback that intercepts persistence. This is
mostly correct. The current extension points are:

- An Agent module can override `checkpoint/2` and `restore/2`.
- A Plugin can own portable state through `state_spec/1` and
  `update_state/3`. The default Agent checkpoint includes this state.
- A persistence adapter can replace the byte store.
- Commit telemetry can observe the result. It cannot change the result.

Do not add `before_persist`, `after_persist`, or `around_persist` Plugin
callbacks. Such callbacks would let a Plugin change commit order, perform I/O
inside the commit, hide an uncertain write, or depend on a runtime that does
not exist yet during restore. An `after_persist` failure also cannot undo a
successful durable write.

One smaller Plugin extension does match the current ownership model. A reusable
Plugin owns its state schema, but today the Agent module must migrate old
stored values for that Plugin. Add this optional pair:

```elixir
@callback checkpoint_state(
            plugin_state :: term(),
            context :: map(),
            opts :: keyword()
          ) :: {:ok, portable_state :: term()} | {:error, term()}

@callback restore_state(
            portable_state :: term(),
            context :: map(),
            opts :: keyword()
          ) :: {:ok, plugin_state :: term()} | {:error, term()}
```

Rules:

- A Plugin must define both callbacks or neither callback.
- A Plugin must own a state key before it can define the callbacks.
- Each callback receives only that Plugin's state slice. It cannot inspect or
  change domain state, another Plugin's state, the persistence key, the record
  revision, adapter options, or the write result.
- The callbacks receive no runtime reference and must not depend on a Plugin
  process or external side effect.
- The checkpoint result must be portable.
- The restored value must pass that Plugin's current state schema.
- Jido calls the callbacks in declared Plugin order and stops on the first
  error.
- `Jido.Agent.default_checkpoint/2` and `default_restore/3` use these callbacks.
  An Agent that fully replaces those functions owns the complete custom format
  and its migrations.

This pair lets a Plugin version or reduce its stored state without access to
the storage transaction. It does not let a Plugin change persistence policy.

Do not add a public full-record codec in this implementation. A future
`Jido.Persistence.Codec` could add compression, encryption, or an outer storage
envelope between record validation and the adapter. That design needs key
rotation, format identification, size limits, and compare-and-swap tests. Ecto,
Bedrock, and Redis do not need it.

## Topology persistence scope

This plan covers the durable state of each Agent in a Topology. The current
Topology controller resolves the Jido instance adapter and loads each member
Agent through `Jido.Persistence`. Existing tests prove that member state can
survive a controller restart when the application supplies the same Topology
instance again.

This is not complete Topology persistence. The current controller does not
store these values:

- The Topology instance input.
- The desired member set.
- The Topology definition revision.
- The controller repair target or progress.
- Bus processes, subscriptions, PIDs, or runtime relationship bindings.

The last group is runtime state and should not be stored. The controller can
rebuild it. The first three values are durable desired state if Jido must
recover a Topology without the application supplying the instance again.

Do not extend `Jido.Persistence.Adapter` with Topology callbacks or a multi-key
transaction. This would give Ecto and Bedrock a stronger contract than Redis
and File can provide. It would also make a Topology commit depend on every
member write.

Use the Topology owner Agent for complete Topology durability:

```text
commit portable desired input and definition revision in the owner Agent
  -> confirm the owner Agent compare-and-swap
  -> reconcile member Agents from that committed desired state
  -> restore each existing member through normal Agent persistence
  -> rebuild Buses, subscriptions, and runtime relationship bindings
```

`use Jido.Topology` already creates an owner Agent definition, but the current
controller does not use that Agent as its reconciliation authority. Completing
this model needs the separate Topology owner and live target design. It also
needs the definition revision work that this adapter plan defers.

Add compatibility tests to this adapter work. For each durable adapter, start a
fixed Topology supplied by the application, commit member state, restart the
controller and Jido instance, and confirm that member state restores while
runtime resources rebuild. These tests pressure-test multi-record use without
claiming an atomic Topology commit.

## Ecto adapter

### Modules

- `Jido.Persistence.Ecto`
- `Jido.Persistence.Ecto.Migrations`
- A private query module or schema, only if the query code needs it.

### Dependency

Add this optional runtime dependency:

```elixir
{:ecto_sql, "~> 3.13", optional: true}
```

The host application must also add its database driver. Jido must compile and
run without Ecto. Adapter option validation must return a clear missing-package
error when Ecto is not present.

`Jido.Persistence.Ecto` must always compile. It is a small public wrapper that
has no compile-time Ecto macro or struct reference. It checks for Ecto and then
calls a private Ecto implementation. Compile that private implementation only
when Ecto is present.

`Jido.Persistence.Ecto.Migrations` must also compile without Ecto. Its macro
must give a clear error when an application tries to use it without Ecto. The
quoted migration can use `Ecto.Migration` only in the caller that has installed
Ecto.

### Table

Use one new v3 table. Do not reuse the v2 `jido_checkpoints` table.

```text
jido_persistence_records
  key_hash  binary(32), primary key
  key       binary, not null
  value     binary, not null
```

The key hash keeps the primary key small. The stored key detects a hash
collision. The migration helper must require `version: 1`. Support an optional
Ecto `:prefix`.

Support PostgreSQL and SQLite in the first release. Do not claim support for a
database until its compare-and-swap and migration tests pass.

### Options

Required:

- `:repo`

Optional:

- `:prefix`
- `:table`, default `"jido_persistence_records"`
- `:repo_options`, default `[]`

Pass `:repo_options` to Ecto Repo calls. The nested list keeps backend options
out of the Jido adapter API. Reject unknown top-level adapter options. The
migration helper and adapter must use the same `:prefix` and `:table` values.

### Operations

- `get/2`: select by `key_hash`, verify `key`, and return `value`.
- Missing row: return `{:error, :not_found}`.
- Hash collision: return `{:error, :key_collision}`.
- Create CAS: use `insert_all` with `on_conflict: :nothing`. One inserted row is
  success. Zero rows is a conflict.
- Replace CAS: use one `update_all` query that matches `key_hash`, `key`, and the
  complete expected `value`. One changed row is success. Zero rows is a
  conflict.
- Do not use a Repo `get` followed by a Repo `update` as the atomic operation.
- Let unexpected Repo write failures raise through the core fault boundary.
  Core will classify a compare-and-swap exception as an uncertain write.

## Bedrock adapter

### Module

- `Jido.Persistence.Bedrock`

### Dependency

Add this optional runtime dependency:

```elixir
{:bedrock, "~> 0.7", optional: true}
```

Do not copy the old `bedrock_raft` override. The host owns the Bedrock Repo and
cluster supervision.

The adapter must not use a Bedrock struct or macro. Call the configured Repo
module through its public functions. This lets the adapter module compile when
Bedrock is not installed. Option validation must return a clear missing-package
error before the first operation.

### Options

Required:

- `:repo`

Optional:

- `:prefix`, default `"jido/v3/"`
- `:transaction_options`, default `[]`

Validate that the Repo exports `transact/1` or `transact/2`, `rollback/1`,
`get/1`, and `put/2`. Pass `:transaction_options` to `transact/2`. This list can
contain Bedrock options such as `:retry_limit` and `:timeout_in_ms`.

### Operations

- Add the configured prefix to the Jido key.
- `get/2`: run `repo.get/1` in `repo.transact/2`.
- CAS: run the read, byte comparison, and `repo.put/2` in one transaction.
- Use a normal read. Do not use a snapshot read or disable conflict checks.
- On a byte mismatch, call `repo.rollback(:conflict)`.
- Let Bedrock retry storage conflicts. The function will read again on a retry.
- Return only an explicit rollback mismatch as `{:error, :conflict}`.
- Treat all other failed or invalid write results as indeterminate.
- Check the complete prefixed key against the 16 KiB key limit.
- Check the value against the 128 KiB value limit before a transaction starts.

The first version stores one Agent record in one Bedrock value. Do not add
envelopes, Thread keys, memory keys, secondary indexes, or adapter telemetry.
Core already owns the record envelope and persistence telemetry boundary.

## Redis adapter

Retain `Jido.Persistence.Redis` and its current option model:

- required `:command_fn`
- optional `:prefix`
- optional millisecond `:ttl`
- one Lua `EVAL` command for compare-and-swap

Remove `put/3` and `delete/2` from the required adapter surface. Keep the v3
record key and value format unchanged. Add Redis to the shared conformance
suite. State that EVAL permission is required.

Do not add Redix, Redis Cluster routing, connection pools, failover policy, or
script caching to core. The host `:command_fn` owns these choices.

## Shared tests

Create one reusable adapter conformance test helper under `test/support`. Run
the same cases for ETS, File, Redis, Ecto, and Bedrock:

1. Missing get.
2. Create when missing.
3. Create conflict when present.
4. Replace exact bytes.
5. Replace conflict on different bytes.
6. Idempotent replacement with equal bytes.
7. Binary keys and values, including zero bytes.
8. Two concurrent writers that read the same value. Exactly one can replace it.
9. A conflict does not change the stored value.
10. Invalid options fail before backend work.
11. A preflight rejection confirms that no write occurred.
12. A plain callback error, exception, or invalid CAS result is classified as
    uncertain by a live Agent Server.

Add core lifecycle tests:

- A new persistent Agent has revision zero in storage before startup returns.
- Initial write conflict prevents readiness and cleans up Plugin runtimes.
- Initial indeterminate write prevents readiness.
- A tombstone blocks restore.
- A tombstone blocks a delayed revision-zero writer.
- Delete conflicts with a concurrent newer commit and does not remove it.
- A custom Agent checkpoint and restore pair works on all real adapters.
- An instance default can be replaced or disabled for one Agent.

Add Plugin state persistence tests:

- A Plugin can round-trip a custom portable form for its own state.
- A Plugin can restore an old state version into its current schema.
- A Plugin cannot define only one callback or define callbacks without state.
- A Plugin cannot change another state key.
- A non-portable checkpoint result fails before backend work.
- A callback error, exception, or invalid result fails checkpoint or restore.
- No Plugin runtime is needed during checkpoint conversion or restore.

Add current Topology compatibility tests:

- Member Agent state restores after controller and Jido instance restart.
- Bus subscriptions and runtime ownership bindings rebuild from the supplied
  Topology instance.
- A tombstoned member is not silently created again.
- One member conflict does not corrupt another member record.
- The tests do not claim that the complete Topology target is stored or changed
  atomically.

Add backend tests:

- Ecto: SQLite tests in the normal suite.
- Ecto: PostgreSQL migration, binary equality, prefix, and concurrent CAS in a
  separate CI job.
- Bedrock: a fast fake Repo in the normal suite.
- Bedrock: a real single-node create, commit, VM or cluster restart, restore,
  conflict, and tombstone test in a separate CI job.
- Redis: the current controlled command tests in the normal suite. Add an
  optional real Redis CI job if the project can own that service reliably.
- File: retain the one-BEAM ownership tests.

Add one small consumer fixture that depends on Jido without Ecto or Bedrock. It
must fetch dependencies, compile, and start Jido. This proves that both new
dependencies are optional for users.

## Implementation sequence

### Phase 1: Freeze the refined contract

1. Add failing tests for revision-zero startup and tombstone deletion.
2. Change `Jido.Persistence.Adapter` to the two required byte operations and
   the strict compare-and-swap result set.
3. Remove core use and validation of raw `put/3` and `delete/2`.
4. Add active-record and tombstone decode paths in `Jido.Persistence`.
5. Change `delete_agent/4` to a tombstone compare-and-swap.
6. Add the Plugin-owned state checkpoint and restore callback pair.
7. Update ETS, File, and Redis to the refined contract.
8. Enable the FA-05 acceptance test without a skip.

### Phase 2: Make revision zero durable

1. Make restore report whether it loaded or prepared a new Agent.
2. Delay Server readiness until a new revision-zero record is confirmed.
3. Clean up provisional Plugin runtimes on conflict or failure.
4. Keep an indeterminate startup unpublished and fail closed.
5. Verify all restore policies and duplicate-start paths.

### Phase 3: Add Ecto

1. Add the optional dependency and conditional compile boundary.
2. Add the one-table versioned migration helper.
3. Add get and atomic CAS.
4. Add SQLite tests and PostgreSQL CI tests.
5. Add setup and data migration documentation.

### Phase 4: Add Bedrock

1. Add the optional dependency.
2. Add option and size checks.
3. Add transactional get and CAS.
4. Add fake Repo tests and real single-node tests.
5. Add setup, cluster ownership, size limit, and recovery documentation.

### Phase 5: Documentation and package checks

1. Add Ecto and Bedrock to the ExDoc persistence module group.
2. Update README and persistence guides with all five adapters.
3. Update `usage-rules.md`, configuration, storage, migration, API migration,
   core scope, and extension boundary documents.
4. Keep the v2 data conversion warning. The new adapters do not read v2
   `jido_ecto`, `jido_bedrock`, or `Jido.Storage.Redis` data.
5. Reset each changed design document to `Pending approval`, as required by
   `docs/design/AGENTS.md`.
6. Build the Hex package and inspect its metadata. Ecto SQL and Bedrock must be
   optional. Database drivers must not be Jido runtime requirements.

## Main files to change

Core:

- `lib/jido/agent.ex`
- `lib/jido/plugin.ex`
- `lib/jido/persistence.ex`
- `lib/jido/persistence/adapter.ex`
- `lib/jido/persistence/ets.ex`
- `lib/jido/persistence/file.ex`
- `lib/jido/persistence/redis.ex`
- `lib/jido/persistence/ecto.ex`
- `lib/jido/persistence/ecto/migrations.ex`
- `lib/jido/persistence/bedrock.ex`
- `lib/jido/agent_server.ex`
- `mix.exs`
- `mix.lock`

Tests:

- `test/jido/persistence_test.exs`
- `test/jido/persistence/adapter_test.exs`
- `test/jido/persistence/ets_test.exs`
- `test/jido/persistence/file_test.exs`
- `test/jido/persistence/redis_test.exs`
- `test/jido/persistence/ecto_test.exs`
- `test/jido/persistence/bedrock_test.exs`
- Plugin contract and Plugin state persistence tests
- `test/jido/topology/controller_test.exs`
- `test/jido/topology/controller/composition_runtime_test.exs`
- `test/support` adapter and Repo fixtures
- `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs`

Documentation:

- `README.md`
- `usage-rules.md`
- `guides/configuration.md`
- `guides/storage.md`
- `guides/persistence-adapters.livemd`
- `guides/compare-and-swap-hibernate-and-thaw.md`
- `guides/migration.md`
- `guides/api-migration-map.md`
- `guides/core-scope.md`
- `docs/design/90_package-boundaries/runtime-extension-boundaries.md`
- `docs/design/README.md`

## Migration rules

### From v2 Ecto

Do not reuse the old three tables as the live v3 store. Stop v2 writers. Read
the old checkpoint and Thread data with v2 code. Convert application state and
Plugin state. Save each new Agent through `Jido.Persistence.save_agent/3` into
`jido_persistence_records`.

### From v2 Bedrock

Use a new prefix, such as `jido/v3/`. Do not read old checkpoint envelopes,
Thread keys, or memory indexes as v3 Agent records. Export and convert with the
old package before cutover.

### From v2 Redis

Use a new prefix. Do not point v3 at the v2 `:cp:` and `:th:` keys. Read v2
checkpoints with `Jido.Storage.Redis`, convert them, and save them through the
v3 persistence API. V2 Thread keys have no direct v3 persistence target.

### From v3 Redis

Keep the current v3 key and value format. The refined adapter contract must not
force a data rewrite. A new tombstone is only a new record kind.

## Verification gates

Run these checks after each phase that changes runtime code:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test test/jido --include flaky --seed 0
mix credo --strict --only warning
mix dialyzer
```

Before merge, also run:

- `mix quality`
- the PostgreSQL adapter job
- the real Bedrock single-node job
- the no-optional-dependencies consumer job
- `mix docs` with warnings as errors
- `mix hex.build`
- the complete relevant example and migration tests
- Elixir 1.18 and OTP 27 beta QA
- coverage at or above the repository gate

## Acceptance criteria

The work is complete when all these statements are true:

- A user can choose ETS, File, Redis, Ecto, Bedrock, or a custom adapter with
  the same Jido persistence API.
- A stateful Plugin can own the durable format and migration of only its state
  slice.
- No Plugin can intercept storage operations or weaken commit ordering.
- Jido installs without Ecto, a SQL driver, Bedrock, or a Redis client.
- Jido starts no backend process.
- A new persistent Agent is durable before startup returns success.
- A live commit uses one atomic expected-byte replacement.
- Two stale writers cannot both commit.
- An unknown write result stops the writer.
- Durable deletion leaves a tombstone and blocks delayed creation.
- Ecto works against tested SQLite and PostgreSQL versions.
- Bedrock works across a real single-node restart and reports its size limit.
- Redis support and the existing v3 Redis data format remain.
- v2 records need an explicit offline conversion.
- The public adapter contract has no Thread, memory, Repo, SQL, Redis, or
  Bedrock type in it.
- A fixed Topology supplied again by the application restores its member Agent
  state and rebuilds its runtime resources on each durable adapter.
- The adapter documentation does not claim complete Topology target
  persistence or a multi-record atomic commit.

## Deferred work

Do not add these items in this implementation:

- Agent discovery scans.
- Automatic activation after a node failure.
- Cluster leases or single-owner election.
- A durable mailbox or Directive outbox.
- Thread journals.
- Bedrock-backed Jido memory.
- Chunked Bedrock Agent records.
- Encryption or compression policy.
- A canonical Agent Ref and stable namespace redesign.
- Definition revision enforcement or live state migration.
- Automatic v2 data conversion.
- Durable Topology desired input, definition revision, and owner-Agent
  reconciliation.

Each item needs its own contract and failure tests.
