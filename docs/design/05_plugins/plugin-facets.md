> Supporting Plugin design. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../../guides/core-scope.md).

# Plugin facets and extension ownership

[Design overview](../README.md) | Related:
[Plugins](plugins.md),
[Instance persistence](../07_persistence/instance-persistence.md), and
[Topology as one Agent authoring host](../11_topology-control-plane/topology-authoring-host.md)

- Status: Proposed plan
- Scope: Agent, Agent Server, Persistence, Topology, and reusable Plugin packages

## Goal

Define four stable Plugin extension points. Each extension point has one owner
and one execution boundary:

1. `Jido.Agent.Plugin` extends portable Agent definition and Turn behavior.
2. `Jido.AgentServer.Plugin` extends one live Agent Server.
3. `Jido.Persistence.Plugin` owns durable conversion for one Agent Plugin state
   slice.
4. `Jido.Topology.Plugin` extends static Topology meaning and planning.

Keep one simple package declaration for a capability that uses more than one
extension point. Do not put the four callback groups in one behavior.

## Decision summary

1. Change `Jido.Plugin` from an execution behavior to a neutral package
   manifest.
2. Put callbacks under the module that owns their execution and failure rules.
3. Permit one manifest to declare zero or one module for each of the four
   facets.
4. Keep Agent facet execution pure and usable without an Agent Server.
5. Keep Persistence facet execution pure and limited to state owned by its
   paired Agent facet.
6. Keep Topology facet execution pure. A Topology capability uses an Agent
   Server facet for live reconciliation.
7. Keep `Jido.Persistence.Adapter` as a separate byte-store contract.
8. Keep Agent and Topology authoring extensions as syntax-lowering contracts.
   They are not Plugin facets.
9. Do not add general hooks before, after, or around persistence operations.
10. Preserve one ordered Plugin declaration list as the user installation API.

This is a closed list for the first design. A new fifth facet needs a new owner
with different state, execution, and failure rules. A new callback alone is not
enough reason to add a facet.

## Why the current contract must change

The implemented `Jido.Plugin` behavior has callbacks from two owners.

Pure Agent work includes:

- Command preparation.
- Owned state schema composition.
- Directive declaration and validation.
- Owned state reduction before commit.

Live Agent Server work includes:

- Input admission through a runtime reference.
- Outbound Signal transformation.
- Runtime child start and readiness.
- Directive work after commit.

The current behavior and normalized Spec join these operations. As a result, a
pure Agent capability has an Agent Server lifecycle shape, and a live-only
runtime capability is stored as part of Agent Plugin configuration. A larger
behavior will make this ownership problem more difficult.

Persistence and Topology add two more valid extension boundaries. They must not
become more optional callbacks on the current behavior.

## Vocabulary

| Term | Meaning |
| --- | --- |
| Plugin package | One reusable capability that a user declares. |
| Manifest | Static metadata that maps a Plugin package to owner-specific facets. |
| Facet | One behavior implemented for one Jido owner. |
| Declaration | A module or `{module, options}` entry supplied by a user. |
| Facet Spec | One validated internal value owned by Agent, Agent Server, Persistence, or Topology. |
| Adapter | A replaceable external service boundary, such as byte storage. It is not a Plugin facet. |
| Authoring extension | Static DSL syntax lowering. It is not an execution extension. |

Use this selection rule:

| Need | Contract |
| --- | --- |
| Add a reusable capability to one Jido owner | Owner-specific Plugin facet |
| Replace an external backend | Adapter |
| Add DSL syntax that lowers to canonical values | Authoring extension |
| Request work after commit | Directive plus Agent Server handler |
| Observe work without changing it | Telemetry or tracer |

`Jido.Exec`, Signal dispatch adapters, persistence adapters, and observation
tracers stay separate. The four facets are not a universal replacement for
each focused behavior.

## Ownership model

```text
                                  Jido.Plugin
                             static package manifest
                                          |
            +----------------+------------+------------+----------------+
            |                |                         |                |
            v                v                         v                v
   Jido.Agent.Plugin  Jido.AgentServer.Plugin  Jido.Persistence.Plugin  Jido.Topology.Plugin
   pure Turn/state    live per-Agent runtime   pure durable slice       pure definition/plan
```

The diagram shows valid information flow, not callback invocation order. The
manifest connects facets. One facet must not call a sibling facet directly.
The owning Jido component coordinates each facet through its public contract.

The core dependency rules are:

- `Jido.Agent` must not depend on `Jido.AgentServer`, `Jido.Persistence`, or
  `Jido.Topology`.
- `Jido.AgentServer` can depend on Agent and Persistence contracts.
- `Jido.Persistence` can depend on portable Agent checkpoint contracts.
- `Jido.Topology` can build Agent definitions and can use Agent Server for live
  activation.
- `Jido.Plugin` manifest code must stay neutral. It contains module identities
  and static configuration only.

## Package manifest

A capability with Agent and Agent Server behavior has this shape:

```elixir
defmodule Jido.Plugin.Scheduler do
  use Jido.Plugin,
    agent: Jido.Plugin.Scheduler.Agent,
    agent_server: Jido.Plugin.Scheduler.AgentServer
end
```

A capability can declare any subset:

```elixir
defmodule MyApp.Capability do
  use Jido.Plugin,
    agent: MyApp.Capability.Agent,
    agent_server: MyApp.Capability.AgentServer,
    persistence: MyApp.Capability.Persistence,
    topology: MyApp.Capability.Topology
end
```

The normal Agent declaration stays small:

```elixir
plugins: [
  {Jido.Plugin.Scheduler, timezone: "Etc/UTC"},
  {Jido.Plugin.Audit, max_entries: 1_000}
]
```

The manifest has no Turn, process, persistence, or planning callbacks. It can
only do these static tasks:

- Declare facet modules.
- Validate common package options.
- Map common options to facet-specific options.
- Declare a stable package and facet revision.

The first implementation should permit at most one module for each facet. A
package that needs multiple modules for one owner must compose them behind one
facet module. This rule keeps ordering and ownership clear.

A facet module declares only one Jido Plugin behavior. Shared implementation
code belongs in ordinary helper modules.

### Options

The manifest owns public package options. Each facet owns only the normalized
options that the manifest gives to it.

The proposed normalized result is:

```elixir
%Jido.Plugin.Spec{
  module: Jido.Plugin.Scheduler,
  options: [timezone: "Etc/UTC"],
  facets: %{
    agent: {Jido.Plugin.Scheduler.Agent, [timezone: "Etc/UTC"]},
    agent_server: {Jido.Plugin.Scheduler.AgentServer, [timezone: "Etc/UTC"]}
  }
}
```

Each owner builds its own Spec from this result. An Agent Spec must not contain
runtime flags or process data. An Agent Server Spec must not contain schemas
that it does not own.

Direct facet declarations are useful for internal contract tests. They are not
the portable public installation form in the first version. Public definitions
declare a package manifest so paired options and required facets cannot drift.

## Facet 1: Agent

### Purpose

`Jido.Agent.Plugin` extends Agent construction and successful Turn assembly. It
must work through direct Agent execution when no Agent Server or Jido instance
exists.

### Owned responsibilities

- One optional portable state key and schema.
- Zero or more Directive types.
- Pure command preparation.
- Directive validation before commit.
- Pure reduction of owned state from owned Directives.

### Proposed callback groups

```elixir
@callback prepare(Jido.Agent.Command.t(), options()) ::
            {:ok, Jido.Agent.Command.t()} | {:error, term()}

@callback state_spec(options()) ::
            :none | {atom(), Zoi.schema()}

@callback directives(options()) :: [module()] | {:error, term()}

@callback validate_directive(struct(), options()) ::
            {:ok, struct()} | {:error, term()}

@callback reduce_directives(term(), [struct()], options()) ::
            {:ok, term()} | {:error, term()}
```

`reduce_directives/3` replaces `update_state/3`. The new name states that the
callback is a pure reducer and that it receives only Directives owned by that
facet.

### Rules

- The facet receives no PID, runtime reference, Jido instance, partition, or
  Agent Server state.
- The facet must not perform I/O or use current time as hidden input.
- An executable cannot change Plugin-owned state.
- The reducer can replace only its complete owned state slice.
- All state and Directive values must satisfy the portable-term contract.
- Declaration order defines preparation and reduction order.

## Facet 2: Agent Server

### Purpose

`Jido.AgentServer.Plugin` extends one live Agent Server. It owns work that
depends on a mailbox, process, clock, connection, external resource, or commit
boundary.

### Owned responsibilities

- Live input admission.
- Outbound Signal transformation.
- One optional supervised runtime root.
- Runtime readiness.
- Post-commit handling for Directives declared by a paired Agent facet.

### Proposed callback groups

```elixir
@callback admit(runtime_ref() | nil, Jido.Agent.Command.t(), options()) ::
            {:ok, Jido.Agent.Command.t()} | {:error, term()}

@callback prepare_dispatch(
            runtime_ref() | nil,
            Jido.Signal.t(),
            Jido.AgentServer.Plugin.SignalContext.t(),
            options()
          ) :: {:ok, Jido.Signal.t()} | {:error, term()}

@callback handles(options()) :: [module()] | {:error, term()}

@callback handle_directive(
            runtime_ref() | nil,
            struct(),
            Jido.AgentServer.Plugin.DirectiveContext.t(),
            options()
          ) :: :ok | {:error, term()}

@callback child_spec(Jido.AgentServer.Plugin.Init.t()) ::
            Supervisor.child_spec()

@callback await_ready(runtime_ref(), options()) ::
            :ok | {:error, term()}
```

`handle_directive/4` replaces `dispatch/4`. This avoids a conflict with Signal
dispatch terminology.

### Rules

- The facet cannot change Agent state.
- Admission finishes before pure Agent preparation starts.
- Directive work starts only after a successful commit.
- Outbound transformation runs at the Server delivery boundary.
- The facet receives narrow, validated context values.
- A runtime child is optional. Process-free handlers still run in a bounded
  Server-owned task.
- A declared runtime that is unavailable is an error. Core must not use the
  process-free path as a fallback.
- Runtime roots use permanent restart. Short-lived work can exist below the
  root.

### Directive ownership link

The Agent facet declares and validates a Directive. The Agent Server facet can
handle it after commit. The manifest connects these two facets.

Validation must reject these cases:

- A Server facet handles a Directive that its paired Agent facet does not own.
- More than one Server facet handles the same Directive.
- A Server facet declares handling but does not implement
  `handle_directive/4`.

A direct Agent Turn can return a Directive without a Server handler. The direct
caller owns the returned Directive batch. A live Agent Server must report an
unsupported Directive if no built-in or Plugin handler exists.

## Facet 3: Persistence

### Purpose

`Jido.Persistence.Plugin` owns the durable representation and migration of one
paired Agent Plugin state slice.

Most Agent Plugins do not need this facet. The default Agent checkpoint stores
their portable state without conversion.

### Proposed callbacks

```elixir
@callback dump(
            plugin_state :: term(),
            Jido.Persistence.Plugin.Context.t(),
            options()
          ) :: {:ok, portable_state :: term()} | {:error, term()}

@callback load(
            portable_state :: term(),
            Jido.Persistence.Plugin.Context.t(),
            options()
          ) :: {:ok, plugin_state :: term()} | {:error, term()}
```

The facet must define both callbacks. The Context contains only stable values
that can affect format selection, such as package ID, Agent module, checkpoint
format version, and facet revision. It contains no adapter module, adapter
options, PID, runtime reference, write result, or complete Agent state.

### Rules

- A Persistence facet requires a paired stateful Agent facet.
- It receives only the state slice owned by that Agent facet.
- `dump/3` output must be portable.
- `load/3` output must pass the current Agent facet state schema.
- Both callbacks are pure and have no external effects.
- Dump follows Agent Plugin declaration order.
- Load follows reverse declaration order if nested conversion is permitted.
  The preferred first design has independent slices, so declaration order does
  not affect meaning.
- A dump error stops checkpoint creation before adapter work starts.
- A load error stops restoration before any Server Plugin runtime starts.

The durable value should include the package ID and facet revision. The
Persistence facet uses that revision to migrate older values. It must not use
the application release version as an implicit format selector.

### Adapter boundary

`Jido.Persistence.Adapter` remains the storage I/O contract:

```text
validated record
  -> Plugin state dump
  -> core record encoding
  -> Adapter compare-and-swap
```

Load uses the reverse direction:

```text
Adapter get
  -> core record decode and validation
  -> Plugin state load
  -> complete Agent validation
  -> Agent Server runtime start
```

A Persistence Plugin must not:

- Intercept `get` or `compare_and_swap`.
- Change Agent identity, storage key, revision, or expected value.
- Change a conflict or uncertain write into success.
- Run work after a successful write.
- Start a process during restoration.

There are no `before_persist`, `after_persist`, or `around_persist` callbacks.
Telemetry observes persistence. It does not change persistence.

Whole-record encryption or compression is not part of this facet. If it is
required, design a separate `Jido.Persistence.Codec` with explicit framing,
key rotation, size, and error rules. A storage backend still uses
`Jido.Persistence.Adapter`.

### Agent checkpoint interaction

The current Agent `checkpoint/2` and `restore/2` callbacks can replace the
complete checkpoint format. This conflicts with state-slice ownership.

Before implementation, select one of these rules:

1. Recommended: Agent callbacks own only domain state conversion. Agent builds
   a canonical checkpoint with current Plugin state. Persistence runs facet
   dump and load around that canonical checkpoint without adding a Persistence
   dependency to Agent.
2. Compatibility: complete custom Agent checkpoints bypass Persistence facets.
3. Strict: reject complete custom Agent checkpoints when a Persistence facet
   is present.

The first rule gives the cleanest long-term boundary. It is also the largest
API change. The compatibility adapter can use the second rule during migration.

## Facet 4: Topology

### Purpose

`Jido.Topology.Plugin` extends static Topology definition and planning. It must
work without starting a Controller, Agent Server, Agent, Bus, or task.

### Initial scope

The first version can:

- Validate package-owned Topology configuration.
- Lower package-owned declarative values into canonical core Topology values.
- Add bounded, owned contributions to a Topology plan.
- Declare stable dependencies between its contributions and core plan entries.

The first version cannot add an arbitrary live resource kind. A contribution
must lower to core-supported Agents, groups, Buses, connections, ownership, or
startup policy. This limit keeps activation and rollback rules inside core.

### Proposed callback shape

```elixir
@callback contribute(
            Jido.Topology.Plugin.Input.t(),
            Jido.Topology.Plugin.Context.t(),
            options()
          ) ::
            {:ok, Jido.Topology.Plugin.Contribution.t()} | {:error, term()}
```

The Input contains the canonical Topology definition and package-owned
declarations. The Context contains stable composition path, instance input,
and limits. The Contribution contains only canonical Topology entries owned by
the facet.

### Rules

- The callback is pure and static.
- The facet cannot start, stop, find, or message a process.
- The facet cannot call a persistence adapter.
- It cannot replace entries owned by core or another facet.
- All produced keys and dependencies must be stable.
- Common Topology validation and size limits run after all contributions.
- Composition uses a defined serial order and rejects duplicate ownership.

Live Topology reconciliation does not belong in this facet. A capability that
needs live reconciliation supplies a paired `Jido.AgentServer.Plugin` facet for
the Topology owner Agent. This keeps desired state in the Agent and makes the
runtime a disposable projection of committed state.

### Authoring extension boundary

`Jido.Topology.Extension` and `Jido.Agent.Extension` remain syntax-lowering
contracts. They can add Spark DSL entities and lower them to package-owned
declarations. Builder and Codec authoring must produce the same canonical
values without Spark.

An authoring extension must not:

- Start runtime work.
- Bypass Plugin facet validation.
- Add a second execution path.
- Become required for Builder or Codec use.

The long-term naming can make this distinction clearer:

```text
*.Extension  -> authoring syntax only
*.Plugin     -> canonical component extension
```

## Capability examples

| Package | Agent | Agent Server | Persistence | Topology |
| --- | :---: | :---: | :---: | :---: |
| Audit | Yes | No | Optional | No |
| Heartbeat | No | Yes | No | No |
| Bus Manager | No | Yes | No | No |
| Bus Client | No | Yes | No | No |
| Signal Dispatch | Yes | Yes | No | No |
| Scheduler | Yes | Yes | Optional for state migration | No |
| Sensor Manager | Yes | Yes | Optional for state migration | No |
| Topology owner capability | Yes | Yes | Optional | Yes |

“Optional” means that the default portable checkpoint is sufficient until the
package needs a different durable representation or a state migration.

## Normalization and storage

One declared package produces one neutral manifest Spec and up to four owner
Specs:

```text
Plugin declaration
  -> validate manifest and common options
  -> select the facet for the current owner
  -> validate facet module and facet options
  -> build owner-specific Spec
```

Recommended Spec modules are:

- `Jido.Plugin.Spec` for the neutral manifest.
- `Jido.Agent.Plugin.Spec` for pure state and Directive ownership.
- `Jido.AgentServer.Plugin.Spec` for runtime and handler ownership.
- `Jido.Persistence.Plugin.Spec` for durable state conversion.
- `Jido.Topology.Plugin.Spec` for static contribution ownership.

An owner Spec must not cache live data. It can contain validated static module
identities, schemas, options, owned types, and ordering data.

The Agent definition keeps canonical Plugin declarations because direct Agent
execution, checkpoint restore, and later Agent Server start must resolve the
same package identity and options. It must not store Server runtime references
or Topology instance data.

## Execution order

### Agent construction

```text
declarations
  -> manifest normalization
  -> Agent facet normalization
  -> unique state and Directive ownership checks
  -> complete Agent schema composition
  -> Agent validation
```

### Direct Agent Turn

```text
Signal
  -> Agent facet preparation
  -> route and execute
  -> protect Agent Plugin state
  -> validate Directives
  -> reduce Agent Plugin state
  -> validate candidate Agent
  -> return candidate and Directives
```

No Server, Persistence, or Topology facet runs in this path.

### Live Agent Turn

```text
Signal
  -> Agent Server facet admission
  -> direct Agent Turn pipeline
  -> Persistence facet dump when persistence is enabled
  -> adapter compare-and-swap
  -> live Agent commit
  -> Agent Server facet Directive handling
  -> outbound Signal transformation and delivery
```

### Restore

```text
adapter get
  -> record decode and validation
  -> Persistence facet load
  -> Agent restore and complete validation
  -> Agent Server facet runtime start
  -> runtime readiness
  -> publish Server as ready
```

### Topology build and activation

```text
authoring input
  -> authoring extension lowering
  -> Topology facet contributions
  -> common definition and plan validation
  -> pure Topology instance
  -> owner Agent start
  -> Agent Server facet reconciliation after committed desired state
```

## Failure and safety rules

- Every public callback return is validated.
- Exceptions, throws, exits, and invalid results become structured errors.
- A pure facet error causes no runtime work and no persistence write.
- A persistence dump error starts no adapter write.
- A persistence load error starts no Agent Server Plugin runtime.
- An adapter conflict cannot be changed by a Plugin.
- An uncertain write removes write authority and stops the Server.
- A post-commit Agent Server Plugin error cannot undo committed state.
- A Topology contribution error starts no topology component.
- One package cannot read or replace state owned by another package.
- Plugin order is stable and explicit. It is not an authorization boundary.

## Compatibility plan

The current `use Jido.Plugin` behavior cannot become a manifest without a
migration period.

Use these compatibility stages:

1. Add the four new behaviors and owner-specific Specs without changing the
   public declaration form.
2. Treat a legacy Plugin module as one package with detected Agent and Agent
   Server facets.
3. Emit a compile warning that lists each callback and its new owner module.
4. Convert built-in Plugins to manifests with named facet modules.
5. Add helpers that create the old declaration form from a new manifest when a
   mixed dependency graph needs it.
6. Mark legacy mixed behavior support as deprecated for the rest of the beta or
   one full minor release.
7. Remove legacy callback detection only in the next permitted breaking
   release.

Do not silently classify an unknown callback. The compatibility normalizer
must have one explicit callback-to-owner table.

## Relation to current design documents

This proposal refines parts of the existing Plugin, runtime topology,
persistence, and Topology owner proposals. Those documents still describe the
current deferred design and can conflict with this proposal.

If this proposal is approved, update the affected documents in one change so
the design set has one definition for Plugin, runtime, persistence, and
Topology ownership. Until then, this document is a review plan and does not
supersede them.

## Implementation plan

### Phase 0: Contract fixtures

1. Add tests that record current Plugin callback order and failure behavior.
2. Add one fixture for each current capability shape: Agent-only, Server-only,
   process-free Server handler, and paired Agent and Server capability.
3. Record current checkpoint and Codec forms for Plugin declarations.
4. Add a dependency check that fails if Agent code calls an Agent Server,
   Persistence, or Topology facet.

Exit condition: the current behavior has complete characterization tests.

### Phase 1: Neutral manifest and owner Specs

1. Add the neutral `Jido.Plugin` manifest metadata contract.
2. Add the four owner-specific Spec modules.
3. Add pure manifest expansion and option-routing validation.
4. Add unique package, state key, Directive, and handler ownership checks.
5. Keep the legacy normalizer as the default path.

Exit condition: new and legacy declarations normalize to equivalent internal
ownership data.

### Phase 2: Agent facet extraction

1. Add `Jido.Agent.Plugin`.
2. Move Agent schema composition and state ownership under it.
3. Move preparation, Directive validation, and state reduction under it.
4. Rename `update_state/3` to `reduce_directives/3` in the new contract.
5. Change direct Agent execution to know only Agent facet Specs.
6. Convert Audit as the first built-in Agent-only package.

Exit condition: direct Agent execution can use an Agent Plugin when no Jido
application or Agent Server is started.

### Phase 3: Agent Server facet extraction

1. Add `Jido.AgentServer.Plugin` and its narrow context structs.
2. Move admission and outbound transformation under it.
3. Move child lifecycle and readiness under it.
4. Move post-commit Directive work under it.
5. Rename `dispatch/4` to `handle_directive/4` in the new contract.
6. Validate Server handlers against paired Agent Directive ownership.
7. Convert Heartbeat and Bus Manager as Server-only packages.
8. Convert Signal Dispatch as the process-backed handler fixture.

Exit condition: Agent Server code does not call an Agent Plugin for live work.

### Phase 4: Paired built-in packages

1. Split Scheduler into manifest, Agent facet, and Agent Server facet.
2. Split Sensor Manager in the same way.
3. Confirm that each capability keeps its present commit, recovery, readiness,
   timeout, and restart behavior.
4. Confirm that the manifest keeps the current one-line Agent declaration.

Exit condition: no built-in module implements callbacks for two owners.

### Phase 5: Persistence facet

1. Resolve the custom Agent checkpoint rule in this document.
2. Add `Jido.Persistence.Plugin` and its Context and Spec.
3. Add stable package and facet revision data to the durable state envelope.
4. Run dump before record encoding and before adapter work.
5. Run load after record validation and before Agent Server runtime start.
6. Use a versioned Scheduler state fixture to prove state migration.
7. Keep the Adapter conformance suite unchanged except for record fixtures.

Exit condition: one Plugin can migrate only its own state slice, and cannot
observe or change the storage transaction.

### Phase 6: Topology facet

1. Define the bounded Topology Input, Context, and Contribution values.
2. Add `Jido.Topology.Plugin` and its Spec.
3. Route Spark, Builder, and Codec forms through one canonical contribution
   pipeline.
4. Limit the first version to canonical core Topology entries.
5. Convert the proposed Topology owner capability to Agent, Agent Server, and
   Topology facets.
6. Prove that plan construction starts no process and performs no I/O.

Exit condition: a package can extend Topology meaning through all authoring
forms and use an Agent Server facet for live reconciliation.

### Phase 7: Public migration and documentation

1. Update module documents and guides to use owner-specific terms.
2. Add a migration table for every old callback.
3. Update Agent and Plugin Codecs with manifest and facet revision rules.
4. Add package-author guidance and four small reference implementations.
5. Remove or schedule removal of the legacy mixed behavior.
6. Update all affected design documents and set them to pending approval.

Exit condition: new packages do not need the legacy behavior, and existing
packages have a mechanical migration path.

## Verification plan

### Architecture tests

- Agent facet files have no dependency on Agent Server, Persistence, or
  Topology modules.
- Each built-in facet module declares one facet marker.
- Manifest expansion is pure, stable, and safe for Codec use.
- Owner Specs contain no fields from another owner.

### Agent tests

- Agent-only Plugins work through direct command execution.
- State key and Directive ownership remain unique.
- Preparation and reduction order stay unchanged.
- A failed callback produces no candidate state.

### Agent Server tests

- Admission runs before Agent preparation.
- Directive handlers run only after commit.
- Process-free and process-backed handlers use the same timeout and failure
  rules.
- Runtime restart uses current committed Agent Plugin state.
- A missing configured runtime is an error.

### Persistence tests

- Dump and load can access only the paired state slice.
- Old facet revisions migrate to the current state schema.
- Non-portable dump output fails before adapter work.
- Load failure starts no runtime.
- Conflict and uncertain-write rules remain unchanged.
- All byte adapters pass the same conformance suite.

### Topology tests

- DSL, Builder, and Codec inputs produce the same canonical contribution.
- A contribution cannot replace another owner's entry.
- Duplicate keys and invalid dependencies fail before activation.
- Plan construction starts no process and performs no I/O.
- Live reconciliation starts only from committed owner state.

### Package checks

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix quality`
- Focused legacy compatibility tests.
- Complete example tests for scheduling, persistence, and Topology.
- Documentation and Hex package build.
- Elixir 1.18 and OTP 27 beta verification.
- Coverage at or above the repository gate.

## Main risks

### A manifest becomes another large behavior

Control: permit only static facet metadata and option routing. Put all work in
owner-specific facets.

### Persistence hooks weaken commit safety

Control: expose only pure owned-slice dump and load. Keep all adapter calls and
write-result handling inside `Jido.Persistence`.

### Topology repeats the Agent and Server mix

Control: keep Topology contribution pure. Put live reconciliation in a paired
Agent Server facet for the owner Agent.

### One declaration hides required runtime behavior

Control: expose facet details through inspection, Codec data, documentation,
and structured startup errors. Convenience must not hide ownership.

### Options diverge between paired facets

Control: validate package options once in the manifest and map them to
facet-specific options before any owner builds its Spec.

### Legacy packages break at once

Control: use explicit legacy callback classification and a staged removal. Do
not require package authors to change declaration sites during the first step.

## Review decisions

Approval of this document should confirm these decisions:

1. The four facet names are `Agent`, `AgentServer`, `Persistence`, and
   `Topology`.
2. `Jido.Plugin` becomes a static package manifest.
3. Persistence Plugins can transform only their paired Agent Plugin state.
4. Persistence Adapters remain separate byte stores.
5. Topology Plugins stay pure and use an Agent Server facet for live work.
6. Agent and Topology authoring extensions stay separate from Plugin facets.
7. A Plugin package has no more than one module for each facet in the first
   version.
8. The new Agent state reducer is named `reduce_directives/3`.
9. The new Server effect callback is named `handle_directive/4`.
10. The current complete custom checkpoint callback gets a separate migration
    decision before Persistence facet implementation.

## Deferred work

- General persistence middleware.
- Whole-record encryption or compression.
- Storage discovery, catalogs, and recovery scans.
- Cluster leases and placement policy.
- Arbitrary new live Topology resource kinds.
- Concurrent facet execution.
- More than one module for the same owner in one package manifest.
- Dynamic Plugin installation into a running Agent.
