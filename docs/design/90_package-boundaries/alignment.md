> Seam alignment plan. This document is pending approval.

# Package and extension boundaries alignment

## Status

- Design reviewed: 2026-09-08. All package-boundary documents are pending
  approval.
- Code reviewed: `1496421f63978c416c0c0a4fc8792935150aecf8`.
- Prerequisite alignment: [00 Overview](../00_overview/alignment.md), used as a
  draft prerequisite only.
- Alignment state: `Draft`.
- Approved decisions: None.

The Overview review status is `Pending approval`. This alignment uses its
Bright Line and package direction as assumptions. It does not call the
Overview approved. The alignment state is execution status, not document
approval.

This document gives outcomes and gates. It is not a formal implementation
plan. After the seam intent and requirements are approved, `ce-plan` follows
approval and creates the implementation plan.

## Inputs and evidence

### Design inputs

- `docs/design/AGENTS.md`: review, EARS, dependency order, and document rules.
- `docs/design/SEAM_TEMPLATE.md`: required three-file seam structure.
- `docs/design/VISION.md`: pending Bright Line and library direction.
- `docs/design/00_overview/design.md`: draft package and extension assumptions.
- `docs/design/90_package-boundaries/design.md`: recommended target for this
  seam.

### Canonical code and package evidence

| Evidence path | Exact current behavior |
| --- | --- |
| `mix.exs:4,351-375` | Jido is version `3.0.0-beta.1`. It uses a sibling path for `jido_action`, a Hex V3 range for `jido_signal`, and no production AI or browser dependency. |
| `../jido_action/mix.exs:263-283` | `jido_action` has no dependency on Jido. |
| `../jido_signal/mix.exs:189-209` | `jido_signal` has no dependency on Jido. |
| `../jido_action/lib/jido_action.ex:1-45` | `jido_action` owns validated Actions. An Action can perform I/O, while its caller owns retry, scheduling, and persistence policy. |
| `../jido_action/lib/jido_exec.ex:1-48` | `Jido.Exec` is the public Action, Instruction, and Flow execution boundary. Its execution values are not durable checkpoints. |
| `../jido_signal/lib/jido_signal.ex:1-49` | `jido_signal` owns the CloudEvents-compatible Signal envelope and custom Signal definitions. |
| `../jido_signal/lib/jido_signal/router.ex:1-61` | The Signal Router returns generic targets in a defined order and does not execute them. |
| `../jido_signal/lib/jido_signal/dispatch.ex:1-17` | Signal dispatch is synchronous. The caller owns asynchronous work, retry, concurrency limits, and circuit breaking. |
| `../jido_signal/lib/jido_signal/bus.ex:1-21` | The local Bus owns ordered delivery and replay. It does not own retry timers, leases, dead letters, or competing-consumer policy. |
| `lib/jido.ex:8-48` | Jido documents immutable Agent values, Actions, Directives, direct commands, and the local runtime relationship. |
| `lib/jido.ex:70-107` | One Jido instance can declare an optional persistence adapter. |
| `lib/jido.ex:144-201` | Instance modules expose Agent lifecycle, ID lookup, PID results, and Registry, supervisor, and Runtime Store name helpers. |
| `lib/jido.ex:346-370` | A local Jido instance starts its Registry, Task Supervisor, Runtime Store, Spawn Registry, and Agent Dynamic Supervisor. |
| `lib/jido.ex:430-684` | The public Jido facade starts, finds, lists, stops, hibernates, and thaws Agents through IDs or live handles. |
| `lib/jido/agent.ex:1-68` | Jido owns the immutable Agent definition and instance. Direct command evaluation returns a candidate and Directives without a live commit. |
| `lib/jido/agent.ex:94-132,370-423` | Agent modules can define complete checkpoint and restore callbacks. |
| `lib/jido/agent/builder.ex:1-18` | Builder creates Agent definitions through the canonical constructor. |
| `lib/jido/agent/codec.ex:1-25` | Codec owns versioned static authoring documents, not Agent checkpoints or effect journals. |
| `lib/jido/agent/extension.ex:1-23` | An Agent authoring extension lowers static syntax to canonical configuration and cannot add another runtime. |
| `lib/jido/topology/extension.ex:1-27` | A Topology authoring extension is static lowering and cannot bypass normal activation or validation. |
| `lib/jido/plugin.ex:1-24,67-102` | One Plugin can own Agent state, pure callbacks, Directives, dispatch, and one runtime root. Runtime dispatch occurs after commit and gets no complete private Server state. |
| `lib/jido/agent/directive.ex:1-15` | A Directive requests runtime work after commit. It does not change Agent domain state or undo Action I/O. |
| `lib/jido/agent_server.ex:160-330` | Agent Server command, request, cancellation, state, readiness, and inspection operations are public and accept PIDs or registered names. |
| `lib/jido/agent_server.ex:1493-1594` | The Server persists before live commit and Directive work. Only uncertain write results always stop the Server; confirmed failures can use the error policy. |
| `lib/jido/agent_server.ex:2874-2929` | Persistent startup restores a record if present, but it does not write an initial record. Live commits use the current state version as the expected revision. |
| `lib/jido/agent_server/options.ex:35-50,377-395` | Public Server options include `spawn_fun` and per-Agent persistence selection or disablement. |
| `lib/jido/persistence.ex:1-16,59-160` | Jido owns persistence keys, record encoding, identity checks, revision checks, checkpoint calls, and physical delete. |
| `lib/jido/persistence.ex:284-371` | Persistence uses private format-version-1 maps. Stored keys and records include Jido instance, Agent module, partition, and Agent ID. |
| `lib/jido/persistence/adapter.ex:1-47` | The adapter stores bytes and supports get, put, atomic compare-and-swap, and delete. It does not inspect checkpoints or own lifecycle policy. |
| `lib/jido/persistence/ets.ex:1-58` | Core includes an in-memory byte adapter. |
| `lib/jido/persistence/file.ex:1-66` | Core includes a file adapter with one-BEAM ownership limits. |
| `lib/jido/persistence/redis.ex:1-56` | Core includes a Redis adapter that receives an application-owned command function. |
| `lib/jido/topology/controller.ex:1-24,73-107` | Core owns static local Topology startup, readiness, automatic or manual repair, and current-target reconcile. It has no live target update or cluster policy. |
| `lib/jido/telemetry.ex:1-30` | Jido emits semantic and legacy Agent Server Telemetry. Metadata is bounded and handlers are observers. |
| `../jido_ai/mix.exs:60-71` | The AI V3 checkout uses sibling paths for Jido, Jido Action, and Jido Signal. |
| `../jido_browser/mix.exs:61-70` | The browser checkout still declares Jido and Jido Action V2 ranges. It is not current V3 compatibility proof. |

### Canonical tests

| Evidence path | Behavior proved |
| --- | --- |
| `test/jido/agent/authoring_extension_test.exs:111-149,214-268` | Agent extensions lower to ordinary definitions, share the runtime and Codec, preserve order, and fail on unclaimed or invalid output. |
| `test/jido/topology/authoring_extension_test.exs:137-288` | Topology extensions lower through the common authoring contract and reject invalid or unclaimed output. |
| `test/jido/plugin/contract_test.exs:490-670` | Plugin preparation order, owned Directive filtering, state ownership, and executable write protection are proved. |
| `test/jido/agent_server/directive_execution_test.exs:27-184,254-350` | Directive validation precedes commit, dispatch follows commit, and later failure preserves committed state. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:152-219,258-326` | Plugin runtimes remain outside Agent state, gate readiness, and restart under Agent Server ownership. |
| `test/jido/instance_helpers_test.exs:53-114` | Default instance lifecycle, ID lookup, PID results, generated-name helpers, hibernate, and thaw are supported. |
| `test/jido/persistence/adapter_test.exs:59-110` | Adapter validation requires the current storage operations, including atomic compare-and-swap. |
| `test/jido/persistence_test.exs:259-357` | Per-Agent adapter selection, compare-and-swap conflict, and the current confirmed-failure policy are supported. |
| `test/jido/persistence_test.exs:395-503` | Physical delete and compare-and-swap behavior are proved. |
| `test/jido/persistence/indeterminate_write_test.exs:35-93` | An uncertain write stops stale evaluation and prevents Directive handling. |
| `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-229` | Scheduler keeps stable occurrence IDs, pending work, acknowledgement, restart recovery, and configurable delivery timing. |
| `test/jido/topology/controller_test.exs:20-330` | Static activation, readiness, local repair, state retention, and cleanup are proved. |
| `test/jido/agent_server/child_placement_test.exs:8-72` | An explicit node is valid owned-child intent and pure evaluation starts no process. |
| `test/jido/agent_server/distributed_child_test.exs:41-109,155-234` | Known-node child start, remote restart, and no local fallback are proved. |
| `test/jido/observe/agent_lifecycle_test.exs:10-44,72-115,235-300` | Direct evaluation emits no runtime events. Handler failure preserves results. Semantic metadata is bounded and commit and settlement stay separate. |

### Retained validation record

On 2026-09-08, the superseded analysis recorded this focused result:

```text
mix test test/jido/persistence/adapter_test.exs \
  test/jido/persistence/indeterminate_write_test.exs \
  test/jido/persistence_test.exs \
  test/jido/instance_helpers_test.exs \
  test/jido/topology/controller_test.exs \
  test/jido/plugin/scheduler/occurrence_recovery_test.exs \
  --include research --seed 0
```

Result: 57 tests passed. This result proves only the selected current
behavior. It does not prove a future package API. This documentation rewrite
did not rerun runtime tests.

## Canonical current baseline

### Packages and dependency direction

- Jido depends on `jido_action` and `jido_signal`.
- `jido_action` and `jido_signal` do not depend on Jido.
- `jido_action` owns executable definitions and in-memory execution.
- `jido_signal` owns the Signal envelope, serialization, routing, dispatch,
  and local bus.
- Jido owns Agent meaning, Plugin composition, candidate assembly, live commit,
  Directives, local runtime, persistence policy, static Topology, errors, and
  Agent observation.
- Jido has no production dependency on an AI or browser package.

### Public extension categories

- Ordinary application code can call and wrap Jido modules and supervise a
  Jido instance.
- Actions and Flows can perform I/O. They run through `Jido.Exec`. Jido cannot
  roll back completed external I/O when a later commit fails.
- Signals and Router targets come from `jido_signal`. Signal Dispatch and Bus
  have their own adapter and store boundaries.
- A Plugin combines defined Agent and Agent Server lifecycle points. It can own
  one state key, typed Directives, post-commit dispatch, and one runtime root.
- `Jido.Persistence.Adapter` is a byte-store contract. Jido owns record meaning
  and storage-result handling.
- Agent and Topology extensions lower static DSL declarations to canonical
  values. They do not create a separate runtime.
- A Directive is typed post-commit work. It is not middleware and has no
  general crash-recovery guarantee.
- The Scheduler Plugin is one capability-specific recovery pattern. Its
  `delivery_interval` changes retry timing without changing pending work,
  occurrence identity, or acknowledgement.
- Telemetry handlers observe bounded events. They have no execution authority.

### Supported public APIs

- Direct and DSL Agent authoring, Builder, Codec, custom routing, Agent
  authoring extensions, and complete checkpoint callbacks are supported.
- Instance lifecycle helpers and public PID-based Agent Server operations are
  both supported.
- Registry, Agent Supervisor, Task Supervisor, and Runtime Store name helpers
  are public.
- `spawn_fun`, owned children, explicit known-node child placement, and static
  local Topology are supported.
- Instance persistence defaults and per-Agent adapter overrides or disablement
  are supported.
- ETS, File, and Redis persistence adapters are in Jido core.
- Semantic Telemetry, legacy Agent Server Telemetry, `Jido.Observe`, tracing,
  and local debug paths coexist.

### Current limits

- Core has no stable Agent Ref. Runtime lookup and storage identity use
  different data.
- Jido has no instance-level command, cast, request, or cancellation facade.
- Persistence records are private maps with format version 1. They have no
  public operation ID, storage token, durable lifecycle status, source Signal
  ID, or definition revision.
- A new persistent Agent can become ready before its first record write.
- Normal delete removes the stored value and revision history.
- Only uncertain persistence writes always remove the current activation.
- Static Topology has no live target replacement, cluster placement, or
  ownership transfer.
- Core does not implement automatic recovery scans, leases, leader election,
  placement, transport gateways, durable Agent mailboxes, exactly-once
  delivery, application checkpoint migration, or durable audit history.
- Jido Browser does not yet show V3 dependency compatibility.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirements | Current evidence | Difference | Recommended disposition |
| --- | --- | --- | --- | --- |
| `PKG-GAP-001` | `PKG-REQ-007` through `PKG-REQ-016`, `PKG-REQ-034` | Public modules and tests in the evidence tables | No one inventory classifies every extension entry as retained, staged, or proposed. | `Change documentation`: keep the inventory in this seam and close release status in seam 99. |
| `PKG-GAP-002` | `PKG-REQ-017` through `PKG-REQ-024` | Core tests compile inside the Jido project | There is no small external Mix package that proves public-only Plugin, persistence, Signal, and known-node use. | `Change evidence`: add a public-only acceptance fixture after approval. |
| `PKG-GAP-003` | `PKG-REQ-003` through `PKG-REQ-006`, `PKG-REQ-037`, `PKG-REQ-038` | `mix.exs:351-375`; sibling `mix.exs` files | No one result proves a publishable compatible V3 set. Jido AI uses paths, and Jido Browser declares V2 ranges. | `Change evidence`: define and test one release matrix. |
| `PKG-GAP-004` | `PKG-REQ-023`, `PKG-REQ-034` | `lib/jido.ex:144-201`; `lib/jido/persistence.ex:153-160` | Core has no stable Agent Ref. PID, Registry, and storage identities differ. | `Change, staged`: add the owner-seam identity contract before API restriction or key migration. |
| `PKG-GAP-005` | `PKG-REQ-020`, `PKG-REQ-034` | `lib/jido.ex:187-201,380-415`; `test/jido/instance_helpers_test.exs:67-79` | Generated-name helpers are public, but an external package must not need private runtime names. | `Retain and classify`: preserve the helpers for application use; do not make them a required ecosystem dependency. |
| `PKG-GAP-006` | `PKG-REQ-025` through `PKG-REQ-027`, `PKG-REQ-035` | `lib/jido.ex:70-107`; `lib/jido/agent_server/options.ex:377-395` | Instance defaults and per-Agent persistence selection coexist. One-instance authority is only a proposal. | `Retain`: defer any authority change to seams 07 and 09 with a staged migration. |
| `PKG-GAP-007` | `PKG-REQ-011`, `PKG-REQ-025` through `PKG-REQ-027` | `lib/jido/persistence/{ets,file,redis}.ex` | Core contains three provider implementations. There is no approved rule for moving a production provider to another package. | `Decide`: keep current modules until dependency, ownership, and migration effects are proved. |
| `PKG-GAP-008` | `PKG-REQ-034`, `PKG-REQ-036` | `lib/jido/persistence.ex:284-371` | Current records use one private format and have no migration dispatcher. | `Change, staged`: owner seams define separate format, state, and backend migration rules. |
| `PKG-GAP-009` | `PKG-REQ-026`, `PKG-REQ-034` | `lib/jido/agent_server.ex:2874-2929`; `lib/jido/persistence.ex:137-151` | Initial active records, tombstones, definition revision, and strict write-authority loss are not implemented. | `Defer details`: seams 03, 07, 08, and 09 own the contracts and migration. |
| `PKG-GAP-010` | `PKG-REQ-028` through `PKG-REQ-032` | Topology and child-placement evidence in the test table | Local static control and known-node placement exist. General cluster and transport services do not. | `Retain and bound`: keep current core features; keep general policies outside core. |
| `PKG-GAP-011` | `PKG-REQ-002`, `PKG-REQ-030` through `PKG-REQ-033`, `PKG-REQ-039` | No released durable, cluster, or fabric contract is present in this repository | Earlier package lists describe desired capabilities but do not prove APIs. | `Defer`: treat package names and APIs as proposals until their owners supply design and evidence. |
| `PKG-GAP-012` | `PKG-REQ-033`, `PKG-REQ-037` | `../jido_ai/mix.exs:60-71`; `../jido_browser/mix.exs:61-70` | AI uses the V3 workspace, but browser still selects V2 peers. | `Change evidence`: prove each V3 integration separately. |
| `PKG-GAP-013` | `PKG-REQ-005`, `PKG-REQ-038` | Sibling dependency lists | There is no automated dependency-direction or production-tree guard. | `Change evidence`: make the release gate detect reverse and example-only dependencies. |
| `PKG-GAP-014` | `PKG-REQ-024`, `PKG-REQ-039` | Future provider failure behavior has no package test kit | Core adapter tests do not prove scans, leases, lost replies, cleanup, or backend limits for a future durable package. | `Defer`: each package owns a conformance kit before it claims support. |

## Conflict dispositions

These dispositions preserve the unique earlier proposals without treating them
as approved or implemented.

| Earlier proposal or conflict | Recommended disposition | Owner |
| --- | --- | --- |
| Make one `%Jido.Agent.Ref{namespace, partition, id}` the only identity and require a stable namespace. | Keep stable identity as the direction. Defer its exact value, namespace, and serialization to seam 03. Add it before any restriction of current IDs, PIDs, or names. | 03 Agent identity, 09 Jido instance, 12 Errors and contracts |
| Remove Agent module from durable identity. | Treat this as a key migration, not an additive facade. Define collision, dual-read or offline conversion, rejection, and rollback rules first. | 03 Agent identity, 07 Persistence |
| Add exact public Checkpoint, Commit, and Record structs with operation, Signal, state, storage, and definition revisions. | Preserve these value roles as candidates. Do not lock names or fields in seam 90. | 01 Agent, 03 Agent identity, 06 Commit and effects, 07 Persistence, 12 Errors and contracts |
| Define `active`, `hibernated`, and `deleted` record states, an opaque storage version, one operation ID per write, and optional Turn and source Signal IDs. | Preserve these as record-design candidates. Seam 07 defines lifecycle meaning, token limits, retry identity, and whether a source Signal ID implies no idempotency. | 06 Commit and effects, 07 Persistence, 12 Errors and contracts |
| Make all proposed durable values Zoi-backed and recursively portable. | Keep portable durable data as the direction. Exact types and validation points belong to their value owners. | 01 Agent, 05 Plugins, 07 Persistence, 12 Errors and contracts |
| Require positive definition revision and exact module match at create and restore. | Keep this draft direction as an assumption only. The owner seams define old-checkpoint and executable-code rules. | 01 Agent, 02 Agent authoring, 03 Agent identity, 07 Persistence |
| Replace the byte adapter with `load_agent` and `persist_agent` callbacks over public records. | Keep the current byte adapter and atomic compare-and-swap boundary. Record construction and lifecycle stay above it. | 07 Persistence |
| Remove `put/3` and `delete/2` from the current adapter. | Preserve both supported operations until seam 07 approves a migration. Normal Agent deletion can change separately from storage maintenance. | 07 Persistence, 12 Errors and contracts |
| Give all Agents in one instance one storage provider and remove per-Agent selection. | Preserve instance defaults and per-Agent selection for V3 unless seams 07 and 09 approve and prove a staged change. | 07 Persistence, 09 Jido instance |
| Write an initial revision-zero active record before readiness. | Keep this draft target in the lifecycle owner seams. Seam 90 states only that Jido owns record meaning. | 07 Persistence, 08 Agent Server, 10 Runtime topology |
| Stop write authority after every persistence write error. | Keep this draft target in the commit and persistence seams. Do not claim current confirmed-failure behavior meets it. | 06 Commit and effects, 07 Persistence, 08 Agent Server |
| Use a compare-and-swap tombstone for normal durable delete. | Keep the target in seam 07. Define retention, purge, reactivation, stale-writer, mixed-version, and rollback rules before implementation. | 07 Persistence |
| Make Agent Server PID commands internal and add a Ref-first instance facade. | Add the facade first. Preserve public PID operations until a later deprecation is approved and proved. | 03 Agent identity, 08 Agent Server, 09 Jido instance, 12 Errors and contracts |
| Define instance `call`, `cast`, request, cancellation, lifecycle, and inspection over Agent Ref. | Keep the facade direction. Seam 09 defines exact operations. Any cast remains best effort unless its owner approves a stronger contract. | 09 Jido instance |
| Ban all generated-name helper use. | Preserve public helpers for application composition and observation. An ecosystem package cannot make a generated name a required private dependency. | 09 Jido instance, 12 Errors and contracts |
| Fix creation, activation, commit, deactivation, drain, and cancellation order in this package seam. | Preserve the cross-package boundaries. Move exact state machines and failure meanings to their owner seams. | 06 Commit and effects, 07 Persistence, 08 Agent Server, 09 Jido instance, 10 Runtime topology, 12 Errors and contracts |
| Lock `not_found`, `conflict`, `indeterminate`, `unavailable`, and invalid-data results in seam 90. | Preserve the semantic needs, but let seams 07 and 12 define exact public errors and protocol exceptions. | 07 Persistence, 12 Errors and contracts |
| Give a replacement Plugin runtime matching committed state and state version. | Keep the target, but define its value and restart behavior in Plugin and runtime seams. | 05 Plugins, 08 Agent Server, 10 Runtime topology |
| Call instance infrastructure a Provider and add more provider kinds. | Use Provider only for a separately designed fixed infrastructure boundary. Do not add a generic hook system. | 09 Jido instance and the capability owner |
| Put production database and object-store adapters in `jido_durable`. | Keep provider placement open. Existing ETS, File, and Redis modules stay supported. A future move needs dependency and migration proof. | 07 Persistence, 90 Package boundaries, 99 Delivery |
| Put record, checkpoint, Plugin slice, and backend migrations in one package. | Split core record format, Agent state, Plugin state, and backend schema ownership. | 01 Agent, 05 Plugins, 07 Persistence, adapter owner, host application |
| Treat explicit remote-child node selection as cluster placement. | Keep explicit known-node placement in Jido core. Cluster membership, automatic placement, rebalance, and failover stay outside. | 10 Runtime topology, future cluster owner |
| Let a cluster directory authorize a commit. | Reject. A location result is not durable write authority. | 03 Agent identity, 07 Persistence, future cluster owner |
| Let transport inspect checkpoints or commits. | Reject. Transport delivers a Signal through a public boundary. A durable inbox remains separate from Agent persistence. | `jido_signal`, 09 Jido instance, future transport owner |
| Remove Builder, Codec, logical relationships, or local debug paths as part of the package split. | Remove the removal proposal. Keep the supported APIs until an explicit staged migration. | 02 Agent authoring, 08 Agent Server, 10 Runtime topology, 13 Observability |
| Treat a Directive as exactly-once or durable delivery. | Reject. Capability-specific saved intent and acknowledgement provide recoverable work. | 05 Plugins, 06 Commit and effects |
| Treat Action I/O as part of the Agent commit rollback. | Reject. Jido owns only candidate and live commit semantics. | `jido_action`, 06 Commit and effects |
| Use future durable, cluster, and fabric capability lists as current API. | Keep the lists as proposals. Require public APIs, integration tests, failure tests, and compatible releases before availability claims. | Future package owners, 99 Delivery |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
After approval, `ce-plan` creates the formal implementation plan.

### Phase 0 — Resolve prerequisite and seam decisions

- Requirements: all `PKG-REQ` identifiers.
- Required outcome: approved Bright Line assumptions, ownership matrix,
  extension categories, and conflict dispositions.
- Compatibility: no runtime change.
- Verification: review against the evidence tables and all `PKG-DEC` items.
- Exit criteria: the user approves or changes each package-boundary decision.

### Phase 1 — Lock the public extension inventory

- Requirements: `PKG-REQ-007` through `PKG-REQ-024` and `PKG-REQ-034`.
- Required outcome: one public inventory with owner, authority, support status,
  and migration rule for each extension category.
- Constraints: keep Action, Signal, Plugin, adapter, authoring, Directive,
  Telemetry, and ordinary composition separate.
- Compatibility: all current supported entries remain available.
- Verification: public documentation inventory and a public-only fixture
  specification.
- Exit criteria: seams 01 through 13 can name the package owner for each public
  entry.

### Phase 2 — Set identity and persistence boundary gates

- Requirements: `PKG-REQ-023`, `PKG-REQ-025` through `PKG-REQ-027`,
  `PKG-REQ-034` through `PKG-REQ-036`.
- Required outcome: an approved additive identity direction, storage authority
  decision, provider placement rule, and separate migration owners.
- Constraints: preserve the byte adapter, current PID APIs, generated-name
  helpers, and per-Agent persistence selection until staged replacements are
  proved.
- Compatibility: key and record changes have mixed-version and rollback rules.
- Verification: owner-seam acceptance matrices for identity, persistence, and
  public errors.
- Exit criteria: seams 03, 07, 09, and 12 have no conflicting owner assignment.

### Phase 3 — Bound ecosystem services

- Requirements: `PKG-REQ-002`, `PKG-REQ-028` through `PKG-REQ-033`, and
  `PKG-REQ-039`.
- Required outcome: core, durable, cluster, transport, AI, browser, and
  application capabilities each have one owner and no private dependency.
- Compatibility: static local Topology and explicit known-node children stay
  in core.
- Verification: package-specific public contract and failure-test
  specifications.
- Exit criteria: no proposed package behavior is described as available
  without executable evidence.

### Phase 4 — Prove release compatibility

- Requirements: `PKG-REQ-003` through `PKG-REQ-006`, `PKG-REQ-024`,
  `PKG-REQ-037`, and `PKG-REQ-038`.
- Required outcome: one public-only extension result and one explicit,
  publishable V3 package set.
- Compatibility: release sources replace development paths unless an approved
  exception states otherwise.
- Verification: compile, test, dependency-direction, production dependency
  tree, and cross-package acceptance results.
- Exit criteria: seam 99 can state supported version combinations and all
  deferred packages.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `PKG-REQ-001` and `PKG-REQ-002` | `lib/jido.ex:8-48,346-370`; `mix.exs:351-375` | Approved scope inventory that finds no general platform dependency in core. | `Partial` |
| `PKG-REQ-003` | `mix.exs:354`; `lib/jido/agent/command/runner.ex:29-42`; `../jido_action/lib/jido_exec.ex:1-48` | Public-only Action and Flow integration against the release source. | `Partial` |
| `PKG-REQ-004` | `mix.exs:355`; `lib/jido/agent.ex:69-74`; `../jido_signal/lib/jido_signal/router.ex:1-61` | Public-only Signal route, dispatch, and Bus integration against the release source. | `Partial` |
| `PKG-REQ-005` | `../jido_action/mix.exs:263-283`; `../jido_signal/mix.exs:189-209` | Automated reverse-dependency guard. | `Proven` for current manifests |
| `PKG-REQ-006` | Jido AI sibling dependencies; current Jido public modules | Public-only fixtures for each supported integration package. | `Partial` |
| `PKG-REQ-007` | `lib/jido.ex:70-230`; standard child specifications | Application wrapper and supervision fixture. | `Proven` for current composition |
| `PKG-REQ-008` | `../jido_action/lib/jido_action.ex:1-45`; `../jido_action/lib/jido_exec.ex:1-48` | Cross-package owner check for every Jido route target. | `Proven` for current owner |
| `PKG-REQ-009` | `../jido_signal/lib/jido_signal.ex:1-49`; Router, Dispatch, and Bus module evidence | Cross-package owner check for every public Signal integration. | `Proven` for current owner |
| `PKG-REQ-010` | `lib/jido/plugin.ex:1-24,67-102`; `test/jido/plugin/contract_test.exs:490-670` | Public-only Plugin lifecycle fixture. | `Partial` |
| `PKG-REQ-011` | `lib/jido/persistence/adapter.ex:1-47`; Signal and browser adapters have separate owners | Inventory of every adapter and the package that owns it. | `Partial` |
| `PKG-REQ-012` | Agent and Topology extension modules and tests in the evidence tables | Public-only authoring extension fixture. | `Proven` in core |
| `PKG-REQ-013` and `PKG-REQ-014` | `lib/jido/agent/directive.ex:1-15`; Directive and Scheduler tests | Keep post-commit proof and add a public recoverable-capability fixture. | `Partial` |
| `PKG-REQ-015` | `lib/jido/telemetry.ex:1-30`; `test/jido/observe/agent_lifecycle_test.exs:10-44` | External-handler failure case in the public fixture. | `Proven` in core |
| `PKG-REQ-016` and `PKG-REQ-017` | Distinct public modules in the evidence table | Review checklist for every proposed new extension type. | `Partial` |
| `PKG-REQ-018` through `PKG-REQ-023` | Public module docs state some limits; no external fixture checks all limits | Compile and runtime fixture with no private state, message, name, commit, or PID-identity dependency. | `Missing` |
| `PKG-REQ-024` | Current public modules have documentation and core tests | Package-level acceptance rule and required evidence index. | `Partial` |
| `PKG-REQ-025` | `lib/jido/persistence/adapter.ex:1-47`; `test/jido/persistence/adapter_test.exs:59-110` | Run the adapter contract for every retained provider. | `Proven` for current interface |
| `PKG-REQ-026` | `lib/jido/persistence.ex:1-16,59-160,284-371`; Agent Server commit evidence | Preserve owner split through any record redesign. | `Proven` for current split |
| `PKG-REQ-027` | Adapter module documentation; Redis accepts `command_fn` | Provider fixture with the client supervised by the host application. | `Partial` |
| `PKG-REQ-028` | `lib/jido/topology/controller.ex:1-24,73-107`; controller tests | Keep static local acceptance through V3 release. | `Proven` |
| `PKG-REQ-029` and `PKG-REQ-030` | Child-placement and distributed-child tests in the evidence table | Public integration proof that location policy does not grant write authority. | `Partial` |
| `PKG-REQ-031` and `PKG-REQ-032` | Public Signal and Agent boundaries; no transport package contract | Transport fixture that delivers through public Signal input and cannot inspect durable values. | `Missing` |
| `PKG-REQ-033` | Jido AI uses V3 sibling paths; Jido Browser uses V2 ranges | Separate V3 AI and browser compatibility results. | `Conflict` |
| `PKG-REQ-034` | Supported API evidence throughout this document | Release inventory with replacement, deprecation, and support gates. | `Partial` |
| `PKG-REQ-035` | `lib/jido.ex:70-107`; `lib/jido/agent_server/options.ex:377-395`; persistence tests | Owner decision and compatibility proof before any restriction. | `Proven` for current behavior |
| `PKG-REQ-036` | Current format-version rejection and custom checkpoint callbacks | Versioned fixtures for record, Agent, Plugin, and backend migration boundaries. | `Missing` |
| `PKG-REQ-037` | No complete V3 package result | One explicit Jido, Jido Action, Jido Signal, Jido AI, and Jido Browser set. | `Missing` |
| `PKG-REQ-038` | Jido and Jido AI use development paths | Published-source dependency tree or approved exception. | `Conflict` for publication |
| `PKG-REQ-039` | No future durable, cluster, or fabric API is proved here | Documentation review plus public API and acceptance evidence from each future package. | `Partial` |

## Compatibility effects

No deprecation or removal is approved in this seam.

| Area | Compatibility effect and gate |
| --- | --- |
| Agent Ref | Add a new identity and facade beside ID and PID APIs. Define key conversion, collisions, mixed-version behavior, and rollback before storage identity changes. |
| PID Agent Server API | Keep public command, request, cancellation, state, and readiness functions until a replacement is available and a later deprecation is approved. |
| Generated names | Keep current helpers. Classify them as application composition or observation APIs, not required ecosystem internals. |
| Authoring | Keep DSL and direct forms, Builder, Codec, Agent and Topology extensions, custom routing, and complete checkpoint callbacks. |
| Plugins and Directives | Keep current declarations, callbacks, owned state, runtime, and post-commit dispatch. Owner seams define any facet or runtime-init migration. |
| Persistence adapter | Keep binary get, put, compare-and-swap, and delete. A lifecycle tombstone does not require immediate removal of storage maintenance operations. |
| Persistence selection | Keep instance defaults and per-Agent override or disablement until the authority model and transition are approved. |
| Persistence providers | Keep ETS, File, and Redis module APIs. A package move needs dependency, configuration, module-name, and stored-data migration. |
| Durable values | Do not publish new Ref, Checkpoint, Commit, or Record types until owners, fields, validation, serialization, errors, and migration are approved. |
| Static Topology | Keep local definition, Builder, Codec, extensions, Controller, readiness, and repair. Live target update is not a V3 package-boundary gate. |
| Remote children | Keep explicit known-node start and ownership. Do not present it as membership, automatic placement, or failover policy. |
| Observation | Keep semantic and legacy Telemetry, `Jido.Observe`, tracing, and debug paths until seam 13 proves any replacement. |
| Package versions | Test one V3 set. Restore publishable dependency sources before release unless an approved exception exists. |
| V2 stored data | No automatic conversion is implied. Any import or rejection policy needs versioned fixtures and operator rollback limits. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `PKG-BLK-001` | `Blocker` | 00 Overview | The draft Overview package direction and Bright Line are not approved. | Approve or change the related Overview decisions. |
| `PKG-BLK-002` | `Assumption` | 90 Package boundaries | Jido remains the local coordination layer above `jido_action` and `jido_signal`. | Approve or change `PKG-DEC-001`. |
| `PKG-BLK-003` | `Assumption` | 03 Agent identity, 09 Jido instance | A stable Agent identity is additive before current PID and name APIs change. | Approve the direction and define the identity contract. |
| `PKG-BLK-004` | `Blocker` | 07 Persistence, 09 Jido instance | One-instance storage authority conflicts with supported per-Agent selection. | Approve retention or a staged replacement. |
| `PKG-BLK-005` | `Blocker` | 07 Persistence, 90 Package boundaries | Production adapter placement is not final. | Decide provider ownership from dependency and migration evidence. |
| `PKG-BLK-006` | `Assumption` | 10 Runtime topology | Static local Topology and explicit known-node child placement remain core V3 contracts. | Approve or change `PKG-DEC-006`. |
| `PKG-BLK-007` | `Assumption` | Future package owners | Durable, cluster, and transport names are working names only. | Add package designs and evidence before an availability claim. |
| `PKG-BLK-008` | `Blocker` | `jido_browser`, 99 Delivery | The current browser manifest selects V2 Jido packages. | Supply a tested V3 dependency set. |
| `PKG-BLK-009` | `Blocker` | 99 Delivery | No public-only external fixture or complete V3 matrix exists. | Define and pass both release gates. |
| `PKG-BLK-010` | `Assumption` | 12 Errors and contracts | Existing public maps, tuples, atoms, PIDs, and names can remain documented protocol values during migration. | Complete the seam-12 public contract inventory. |

## Completion criteria

- [ ] The user has approved or changed each `PKG-DEC` item.
- [ ] The Overview dependencies used here are approved or replaced by explicit
      package-seam assumptions.
- [ ] Every approved `PKG-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains in the acceptance matrix.
- [ ] Every public extension entry has one owner, one authority, one support
      status, and one migration rule.
- [ ] No ecosystem package needs private Agent Server state, messages, or
      generated runtime names.
- [ ] Stable identity, persistence authority, provider placement, and stored
      migration ownership have approved owner-seam contracts.
- [ ] A public-only external package fixture passes.
- [ ] One explicit, publishable V3 package set passes its compile, test,
      dependency-direction, and integration gates.
- [ ] Future durable, cluster, and transport behavior is either proved by its
      package owner or marked as proposed.
- [ ] After approval, `ce-plan` creates the formal implementation plan.
