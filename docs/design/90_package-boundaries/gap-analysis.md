# Package boundary gap analysis

> Analysis date: 2026-09-08. This report describes the implemented `v3-spike`
> baseline and compares it with the pending package-boundary design. A proposal
> in this report is not an implemented contract.

## Scope and owner

This report covers the seam between Jido core and extension packages. It
focuses on these subjects:

- package ownership;
- dependency direction;
- public adapters and extension points;
- core scope and ecosystem scope;
- V2-to-V3 and stored-data migration boundaries.

The `jido` package owns the Agent value, the Agent Server, the Jido instance,
Plugins, Directives, persistence record handling, owned child Agents, and the
current static Topology runtime. It consumes Action and Signal contracts from
`jido_action` and `jido_signal`. It must not move Action or Signal ownership
back into Jido core. `mix.exs:351-375` declares this dependency direction, and
`guides/extension-boundaries.md:23-33` states it as a public package rule.

This report does not review the complete Agent, Plugin, persistence, instance,
or topology design. It uses those seams only where they directly define a
package boundary.

## Status terms

- **Current fact** means that code under `lib`, its public module
  documentation, and tests support the statement.
- **Design proposal** means that the pending design requests the behavior, but
  current code does not supply it.
- **Owner decision needed** means that two documents assign different owners,
  or that no document assigns one owner.

## Implemented baseline

The following list is the current baseline. It is not a list of future work.

1. **Current fact — package dependencies.** Jido directly depends on
   `jido_action` and `jido_signal`. The current checkout uses a sibling path for
   `jido_action` and a Hex requirement for `jido_signal` (`mix.exs:351-355`).
   The package guides assign executable contracts to Jido Action and Signal,
   Router, Bus, and Dispatch contracts to Jido Signal
   (`guides/extension-boundaries.md:23-33`).

2. **Current fact — public instance lifecycle.** A Jido instance starts, finds,
   lists, stops, hibernates, and thaws Agents. It returns PIDs for live Agents.
   It does not supply instance-level `call`, `cast`, request, or cancellation
   functions (`lib/jido.ex:144-201`, `lib/jido.ex:430-554`, and
   `lib/jido.ex:631-684`).

3. **Current fact — public PID-based actor API.** `Jido.AgentServer` publicly
   supplies `call/3`, `cast/2`, `send_request/3`, `cancel/2`, `cancel_turn/3`,
   state reads, readiness, and PID or registered-name addressing
   (`lib/jido/agent_server.ex:160-330`).

4. **Current fact — Plugin boundary.** A Plugin can own portable state, prepare
   and admit a command, transform outbound Signals, validate and reduce its
   Directives, dispatch work after commit, and own one supervised runtime root.
   The runtime does not receive the complete private Agent Server state
   (`lib/jido/plugin.ex:2-24` and `lib/jido/plugin.ex:67-102`).

5. **Current fact — persistence boundary.** `Jido.Persistence` owns record
   keys, record encoding, identity checks, revision checks, checkpoint calls,
   restore calls, and adapter fault containment. An adapter stores binary keys
   and binary values (`lib/jido/persistence.ex:1-16` and
   `lib/jido/persistence/adapter.ex:1-44`).

6. **Current fact — atomic commit storage.** Agent Server commit writes use an
   expected revision and adapter compare-and-swap before live state changes and
   before Directive dispatch (`lib/jido/agent_server.ex:1493-1545` and
   `lib/jido/agent_server.ex:2907-2929`). An uncertain write stops the current
   Server. A confirmed conflict can use the configured error policy and can
   leave the Server alive (`lib/jido/agent_server.ex:1548-1578`).

7. **Current fact — current persistence identity.** A stored Agent key includes
   the Jido instance module, Agent module, partition, and Agent ID. The record
   repeats and validates these values (`lib/jido/persistence.ex:153-160` and
   `lib/jido/persistence.ex:284-366`). There is no `Jido.Agent.Ref`.

8. **Current fact — persistence selection.** The instance can declare one
   default adapter. An Agent start can override or disable it with the
   `:persistence` option (`lib/jido.ex:70-107` and
   `lib/jido/agent_server/options.ex:377-395`).

9. **Current fact — initial durability.** A new persistent Agent can become
   ready at revision zero without a stored record. The first successful Turn,
   hibernate, or clean stop writes it. Startup restores a record when it exists,
   but the missing-record path returns the supplied Agent without a write
   (`lib/jido/agent_server.ex:2874-2905`).

10. **Current fact — local topology control.** Core includes a static local
    Topology controller with automatic or manual repair. It has no live target
    updates, cluster placement, or ownership transfer
    (`lib/jido/topology/controller.ex:2-23` and
    `lib/jido/topology/controller.ex:73-107`).

11. **Current fact — explicit remote children.** Core supports explicit Erlang
    node selection for an owned child. The target instance owns the process and
    the parent owns the logical relationship
    (`docs/design/10_runtime-topology/remote-owned-children.md:9-29`). It does
    not supply membership, placement policy, rebalance, or failover.

12. **Current fact — migration.** V3 has no compatibility mode, automatic code
    rewrite, or automatic V2 stored-data conversion
    (`guides/migration.md:1-6`). Applications must migrate Jido Action and Jido
    Signal at the same time (`guides/migration.md:60-94`). Persistence accepts
    only record format version 1 and has no record-format migration dispatcher
    (`lib/jido/persistence.ex:22-23` and `lib/jido/persistence.ex:324-366`).

## Aligned contracts

These current contracts align with the package-boundary direction.

### Clear lower-layer dependency direction

Jido uses Action, Flow, Instruction, execution, Signal, Router, Bus, and
Dispatch contracts from the two lower-level packages. The public extension
guide tells an extension to integrate at those owners instead of duplicating
their systems (`guides/extension-boundaries.md:23-33`). This agrees with the
package-boundary goal that Jido coordinates other packages around an Agent
Turn.

### A narrow byte-store adapter

The adapter does not inspect checkpoints or own Agent lifecycle policy. The
host application supervises an adapter resource
(`lib/jido/persistence/adapter.ex:2-8`). `Jido.Persistence` builds and validates
the record (`lib/jido/persistence.ex:284-366`). This split is suitable for an
external storage implementation.

### Compare-and-swap before commit

The Server saves the next revision before it changes live Agent state or starts
Directive work (`lib/jido/agent_server.ex:1493-1545`). The adapter contract
requires one atomic compare-and-swap operation
(`lib/jido/persistence/adapter.ex:23-41`). Tests reject an adapter without the
operation (`test/jido/persistence/adapter_test.exs:66-77`), prove stale-write
conflict behavior (`test/jido/persistence_test.exs:305-357`), and prove that an
uncertain write prevents later Action execution
(`test/jido/persistence/indeterminate_write_test.exs:46-93`).

### Plugin isolation and post-commit work

The public Plugin documentation says that pure state work runs before commit
and runtime Directive dispatch runs after commit. It also says that a runtime
does not receive private Server state (`lib/jido/plugin.ex:13-24`). The Server
commit path creates reply and Directive actions only after persistence and live
state replacement (`lib/jido/agent_server.ex:1493-1545`). This is the correct
extension direction for reusable Agent capabilities.

### Local repair and explicit placement stay distinct

The current Topology controller repairs one existing local target. It does not
claim cluster placement or ownership transfer
(`lib/jido/topology/controller.ex:12-23`). The remote-child contract selects one
known node without adding cluster policy
(`docs/design/10_runtime-topology/remote-owned-children.md:9-29`). This aligns
with the proposed `jido_cluster` responsibility for membership, placement,
rebalance, and failover
(`docs/design/90_package-boundaries/runtime-extension-boundaries.md:380-401`).

### The migration guide does not claim compatibility

The migration guide clearly says that V2 stored values are not converted and
that adjacent V3 packages must move together (`guides/migration.md:1-13` and
`guides/migration.md:60-94`). This prevents users from treating an unchanged
module name as an unchanged package contract.

## Gaps

### Missing implementation

All items in this section are design proposals, not current API.

#### 1. Stable Agent reference and namespace

The proposal makes `%Jido.Agent.Ref{namespace, partition, id}` the only Agent
identity and requires a stable instance namespace
(`docs/design/90_package-boundaries/runtime-extension-boundaries.md:55-87`).
Current code has no `Jido.Agent.Ref`. Registry identity uses instance plus
partition plus ID, while persistence identity also includes the Agent module
(`lib/jido.ex:545-553` and `lib/jido/persistence.ex:153-160`).

#### 2. Ref-first instance command API

The proposal puts command, request, cancellation, lifecycle, and inspection
operations on the instance facade
(`docs/design/90_package-boundaries/runtime-extension-boundaries.md:209-240`).
Current instance helpers cover lifecycle and PID lookup only. Commands remain
public PID-based `Jido.AgentServer` functions (`lib/jido.ex:144-201` and
`lib/jido/agent_server.ex:160-330`).

#### 3. Public durable values and lifecycle records

The proposed `Jido.Agent.Checkpoint`, `Jido.Agent.Commit`, and
`Jido.Persistence.Record` structs do not exist. Current persistence uses private
maps encoded as Erlang terms (`lib/jido/persistence.ex:284-325`). Current
records have no operation ID, storage-version token, durable lifecycle status,
or source Signal ID.

#### 4. Initial record, tombstone, and definition revision

Current startup does not write revision zero before readiness, deletion uses a
blind adapter delete, and an Agent definition has no required positive
definition revision (`lib/jido/agent_server.ex:2874-2905`,
`lib/jido/persistence.ex:137-151`, and `lib/jido/agent.ex:96-123`). The proposed
fixed creation, deletion, and restore rules therefore do not exist.

#### 5. Instance-only storage authority

The proposal requires one persistence provider per instance and removes
per-Agent selection
(`docs/design/90_package-boundaries/runtime-extension-boundaries.md:168-207`).
Current `AgentServer.Options` explicitly accepts a per-Agent override
(`lib/jido/agent_server/options.ex:47-50` and
`lib/jido/agent_server/options.ex:377-390`).

#### 6. Strict write-failure authority rule

The proposal stops the current Server after every persistence write error
(`docs/design/90_package-boundaries/runtime-extension-boundaries.md:185-199`).
Current code always stops for uncertain errors, but sends confirmed errors such
as `:conflict` to the configured error policy
(`lib/jido/agent_server.ex:1548-1578`). The all-errors rule is not implemented.

#### 7. Durable, cluster, and fabric packages

The proposed catalog scans, recovery controller, leases, fencing, distributed
directory, placement, rebalance, failover, gateways, remote correlation, and
durable inbox are not implemented in Jido core. The seam correctly lists them
as package proposals
(`docs/design/90_package-boundaries/runtime-extension-boundaries.md:361-419`).
No code in this repository proves those future package APIs.

#### 8. Stored-data migration contracts

Core rejects a record whose format does not equal version 1
(`lib/jido/persistence.ex:324-366`). Agent modules can replace `checkpoint/2`
and `restore/2`, but there is no public staged migration contract, Plugin slice
migration contract, record migration registry, or V2 import contract
(`lib/jido/agent.ex:128-132`).

### Design/code conflict

These items are explicit differences between the proposal and current code.
They are not claims that current code already implements the proposal.

#### 1. One provider conflicts with current per-Agent overrides

The proposal says that an Agent Server cannot select or replace its instance
provider (`runtime-extension-boundaries.md:205-207`). Current startup options
allow a caller to override or disable persistence for each Agent
(`lib/jido/agent_server/options.ex:377-390`). The migration impact is high
because tests and examples use this option directly, for example
`test/jido/persistence_test.exs:259-268`.

#### 2. The proposed minimum adapter conflicts with the required behavior

The proposal needs load and persist operations over public records. The
adjacent persistence design reduces the byte adapter to `get/2` and
`compare_and_swap/4`. Current adapter validation requires `get/2`, `put/3`,
`compare_and_swap/4`, and `delete/2`
(`lib/jido/persistence.ex:200-213`). Current public behavior also exposes blind
delete (`lib/jido/persistence.ex:137-151`).

#### 3. Durable creation conflicts with current readiness

The proposal requires a revision-zero record before a persistent Agent becomes
ready (`runtime-extension-boundaries.md:246-261`). Current missing-record
startup returns the supplied Agent and publishes it without that write
(`lib/jido/agent_server.ex:2887-2905`). The adjacent persistence design records
the same known risk (`docs/design/07_persistence/persistence-adapters.md:217-241`).

#### 4. Stable reference identity conflicts with stored key identity

The proposal excludes the Agent module from identity
(`runtime-extension-boundaries.md:55-87`). Current persistence keys include the
Agent module and the instance module atom (`lib/jido/persistence.ex:153-160`). A
Ref migration cannot be an additive facade only. It changes key derivation and
stored-record validation.

#### 5. Private Server commands conflict with the supported public API

The proposal says that Agent Server commands become internal to the instance
(`runtime-extension-boundaries.md:229-235`). Current public documentation and
the migration guide direct callers to `Jido.AgentServer.call/3`, `cast/2`,
requests, and cancellation (`lib/jido/agent_server.ex:160-280` and
`guides/api-migration-map.md:162-185`). The design has no compatibility period,
deprecation sequence, or package-version boundary for this change.

#### 6. The generated-name rule conflicts with current public helpers

The boundary test says that an extension must not construct generated Registry
or supervisor names (`runtime-extension-boundaries.md:430-443`). Current Jido
instance modules publicly return Registry, Agent Supervisor, Task Supervisor,
and Runtime Store names (`lib/jido.ex:187-201`). The design must state which
name functions remain application API and which functions an external package
must not use.

### Missing decision

#### 1. Production adapter ownership

The package seam assigns production database and object-store providers to
`jido_durable`
(`runtime-extension-boundaries.md:361-378`). The adjacent persistence design
proposes `Jido.Persistence.Ecto` and `Jido.Persistence.Bedrock` in core and
keeps Redis in core
(`docs/design/07_persistence/persistence-adapters.md:5-36`). One owner must be
selected before either package API is stable.

#### 2. Migration ownership by layer

The package seam assigns Checkpoint and Record migrations to `jido_durable`,
but lists application checkpoint migrations as a core non-goal
(`runtime-extension-boundaries.md:361-374` and
`runtime-extension-boundaries.md:445-458`). The adjacent persistence design
also proposes Plugin-owned encode and restore callbacks for one Plugin state
slice (`docs/design/07_persistence/persistence-adapters.md:37-41`). The design
does not yet separate these three concerns:

- core record format migration;
- Agent or Plugin application-state migration;
- backend schema and physical storage migration.

Each concern needs one owner, one version source, and one failure rule.

#### 3. AI, browser, and application integration ownership

The package-boundary index says that this seam decides AI and application
package ownership (`docs/design/90_package-boundaries/README.md:3-6`). The main
document discusses only Jido core, `jido_durable`, `jido_cluster`, and
`jido_fabric` (`runtime-extension-boundaries.md:8-10`). It does not define how
`jido_ai`, `jido_browser`, or application packages use Actions, Signals,
Plugins, or instance APIs. The migration guide only warns that a V2 integration
is not proven compatible (`guides/migration.md:92-99`).

#### 4. Static Topology package scope

Current core owns Topology definitions, codecs, extensions, and the local
controller. The package seam assigns only cluster policy to `jido_cluster`.
This is a reasonable split, but the document does not state if static Topology
is a permanent core contract or a temporary spike. Public module grouping
includes all Topology modules (`mix.exs:252-262`).

#### 5. Dependency source and release rule

The current checkout uses a path dependency for `jido_action` and a Hex
dependency for `jido_signal` (`mix.exs:351-355`). The migration guide claims a
version requirement for both packages (`guides/migration.md:60-64`). The seam
does not define the release gate that restores publishable version requirements
or verifies one compatible V3 set.

#### 6. Transition policy for public extension points

The current extension guide lists more supported extension points than the seam
table: tracing, Signal dispatch and buses, Agent and Topology authoring
extensions, builders, codecs, and `spawn_fun`
(`guides/extension-boundaries.md:7-19`). The seam does not say which points are
permanent, transitional, or scheduled for removal. This is important because
the same design proposes to make public Agent Server operations internal.

### Missing verification

#### 1. No external-package contract suite

Most tests compile inside the Jido test environment. They can access modules
and helpers that a released extension package should not use. There is no small
external Mix package that depends only on the published Jido API and proves the
package-boundary test in `runtime-extension-boundaries.md:430-443`.

#### 2. No dependency-direction guard

There is no reported check that fails when Jido reimplements a Jido Action or
Jido Signal contract, or when a lower-level package starts to depend on Jido.
There is also no reported production dependency-tree check that excludes
example-only AI dependencies. The guide states the intended production split
(`guides/core-scope.md:111-116`), but the seam has no acceptance test for it.

#### 3. No compatible V3 package matrix

The repository has a local `jido_action` path and a Hex `jido_signal` version.
The seam has no integration result for a single selected set of Jido,
Jido Action, Jido Signal, Jido AI, and Jido Browser V3 versions. The migration
guide explicitly says that core examples do not prove integration-package
compatibility (`guides/migration.md:80-99`).

#### 4. No migration fixtures

The guides state that automatic conversion does not exist, but there is no
versioned fixture suite that proves a supported V2 import tool, a V3 record
upgrade, or a defined rejection result. Current validation only proves rejection
of the wrong format (`lib/jido/persistence.ex:330-366`).

#### 5. Deferred acceptance tests do not prove package contracts

The core-scope guide says that research tests still record missing identity,
Plugin replacement, durable deletion, and live-upgrade contracts. It also says
that known failing research tests are skipped
(`guides/core-scope.md:91-109` and `guides/core-scope.md:124-135`). These tests
must not be reported as proof of a package API.

#### 6. Package provider failure tests are not defined

Core tests cover adapter conflict and indeterminate writes. The future durable
package still needs a common provider test kit for atomic compare-and-swap,
lost replies, process restart, backend limits, lease loss, tombstone retention,
and scan consistency. The package seam lists these features but gives no shared
test contract (`runtime-extension-boundaries.md:361-378`).

## Narrow dependency notes

These notes describe only dependencies that cross this seam.

1. `jido_action` and `jido_signal` are lower layers. Jido can coordinate their
   values, but it must not own their base execution or transport contracts.

2. `Jido.Plugin` is the current reusable Agent-capability boundary. A package
   can own portable Plugin state and a runtime resource. It cannot read private
   Server state or change committed Agent state outside the Turn path.

3. `Jido.Persistence.Adapter` is below Jido lifecycle policy. The adapter owns
   atomic byte storage. Jido owns record meaning, checkpoint validation,
   revision policy, and write-failure handling.

4. The host application owns external client processes, application-specific
   authorization, business transactions, and data-conversion deployment work.
   A storage adapter must not start its database or Redis client.

5. Static local topology and explicit known-node child start are current core
   features. Membership, automatic placement, rebalance, and failover are
   ecosystem policy. Durable write authority cannot come from a Registry result.

6. A transport package must deliver a Signal through a public Jido boundary. It
   must not inspect checkpoints or Commit data. A durable inbox is separate from
   Agent state persistence.

7. `jido_ai` and `jido_browser` must use the same public Action, Signal, Plugin,
   Directive, and instance contracts as any other extension. No exception for
   private Agent Server access is defined.

## Ordered recommendations

The following items are proposals. They are ordered by dependency and migration
risk.

1. **Lock the ownership matrix first.** Add one table for current and target
   owners. Include Jido Action, Jido Signal, Jido core, static Topology,
   persistence record logic, storage backends, durable recovery, cluster policy,
   fabric, AI, browser, and host-application work.

2. **Resolve production adapter ownership.** Choose if Ecto, Bedrock, and Redis
   adapters are core modules or `jido_durable` modules. Keep record encoding and
   lifecycle policy in Jido core in either case.

3. **Define migration ownership before durable public structs.** Separate core
   record-format migration, Agent and Plugin state migration, and backend schema
   migration. Define the version keys, failure results, rollback limit, and
   operator steps for each layer.

4. **Choose the stable identity and key transition.** Specify how the current
   `{instance module, Agent module, partition, id}` key maps to the proposed
   `{namespace, partition, id}` Ref. Include collision handling, dual-read or
   offline conversion rules, and the point after which old keys are rejected.

5. **Define the public API transition.** State how long PID-based Agent Server
   commands and generated-name helpers remain public. Add the Ref-first instance
   API before any removal. Provide deprecation messages and one release-by-release
   migration table.

6. **Complete the durable core rules as one change set.** Add initial
   revision-zero persistence, public durable values, tombstone deletion, strict
   write results, and one instance storage authority together. Do not expose a
   partial durable contract that permits two writers to select different
   adapters.

7. **Make the current extension inventory complete.** Add the authoring
   extensions, tracing, Signal buses and dispatch, builders, codecs, and
   `spawn_fun` to the seam. Mark each item as retained, transitional, or
   deferred.

8. **Add an external-package test fixture.** Compile a small package against
   only public Jido modules. Prove Plugin runtime use, one persistence adapter,
   Signal delivery, explicit remote-child start, and the absence of private
   Server or generated-name dependencies.

9. **Add a V3 compatibility matrix and release gate.** Test one explicit set of
   Jido, Jido Action, Jido Signal, Jido AI, and Jido Browser versions. Verify the
   production dependency tree and replace local path sources before package
   publication.

10. **Keep future package claims conditional.** Do not describe durable,
    cluster, or fabric behavior as available until a package has public API,
    integration tests, failure tests, and a compatible released dependency set.

## Verification performed for this report

The following focused command passed on 2026-09-08:

```text
mix test test/jido/persistence/adapter_test.exs \
  test/jido/persistence/indeterminate_write_test.exs \
  test/jido/persistence_test.exs \
  test/jido/instance_helpers_test.exs \
  test/jido/topology/controller_test.exs \
  test/jido/plugin/scheduler/occurrence_recovery_test.exs \
  --include research --seed 0
```

Result: 57 tests passed. This result verifies the selected current behavior. It
does not verify any deferred package proposal.

## Evidence reference index

- Package boundary proposal:
  `docs/design/90_package-boundaries/runtime-extension-boundaries.md:21-48`,
  `:50-240`, `:304-359`, and `:361-462`.
- Package index and stated scope:
  `docs/design/90_package-boundaries/README.md:3-13`.
- Current core scope: `guides/core-scope.md:1-22`, `:91-116`, and `:118-135`.
- Public extension guide: `guides/extension-boundaries.md:1-65`.
- Jido instance API: `lib/jido.ex:70-201` and `lib/jido.ex:430-684`.
- Agent Server API and commit order: `lib/jido/agent_server.ex:1-43`,
  `:160-330`, `:1493-1578`, and `:2874-2929`.
- Plugin contract: `lib/jido/plugin.ex:1-41` and `:67-102`.
- Persistence contract and implementation: `lib/jido/persistence/adapter.ex:1-47`
  and `lib/jido/persistence.ex:1-213`, `:240-430`.
- Current Agent checkpoint callbacks: `lib/jido/agent.ex:94-132` and
  `lib/jido/agent.ex:372-405`.
- Current local Topology controller: `lib/jido/topology/controller.ex:1-107`.
- Remote child boundary:
  `docs/design/10_runtime-topology/remote-owned-children.md:9-60`.
- Adjacent persistence decisions:
  `docs/design/07_persistence/persistence-adapters.md:5-59`, `:127-180`, and
  `:180-241`.
- Migration boundary: `guides/migration.md:1-99` and
  `guides/api-migration-map.md:1-83`, `:162-205`.
- Focused tests: `test/jido/persistence/adapter_test.exs:59-110`,
  `test/jido/persistence/indeterminate_write_test.exs:35-115`,
  `test/jido/persistence_test.exs:259-404`, and
  `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-229`.
