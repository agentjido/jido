> Seam alignment plan. This document is pending approval.

# Runtime topology alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `942673bad3b3cd7b2998d74b42ab6311eadafb04` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md),
  [07 Persistence](../07_persistence/alignment.md),
  [08 Agent Server](../08_agent-server/alignment.md), and
  [09 Jido instance](../09_jido-instance/alignment.md). All were used as pending
  draft prerequisites.
- Alignment state: `Blocked` on prerequisite approval and the decisions in this
  seam.
- Approved decisions: None.

The alignment state is execution status. It is not document approval. This file
defines outcomes and gates. It is not the later formal implementation plan.

## Inputs and evidence

### Design inputs

- [Jido V3 vision](../VISION.md): keeps local runtime components in Jido and
  application architecture, network topology, cluster policy, and deployment
  outside Jido.
- [Overview](../00_overview/design.md) and
  [package boundaries](../90_package-boundaries/design.md): keep the local
  runtime, static local Topology, explicit known-node children, and current
  public APIs while deferring general cluster services.
- [Errors](../12_errors-and-contracts/design.md): requires bounded runtime errors
  while preserving registered OTP and compatibility controls.
- [Agent identity](../03_agent-identity/design.md): separates stable Ref,
  replaceable location, and write authority.
- [Plugins](../05_plugins/design.md): keeps permanent Plugin runtime roots and
  requires committed owned state plus matching state version for each start.
- [Commit](../06_commit-and-effects/design.md),
  [Persistence](../07_persistence/design.md), and
  [Agent Server](../08_agent-server/design.md): keep same-instance checkpoints,
  durable records, owner-bound work, and non-replay of transient Directives.
- [Jido instance](../09_jido-instance/design.md): keeps the five-child
  `:one_for_one` tree, local Ref resolution, and no implicit remote forwarding.
- [Target design](design.md): defines the recommended topology contract.

### Canonical code

| Evidence | Canonical current behavior |
| --- | --- |
| `lib/jido.ex:333-370` | The Jido child has a ten-second shutdown and starts Task Supervisor, Registry, Runtime Store, Spawn Registry, and Agent Dynamic Supervisor under `:one_for_one`. |
| `lib/jido.ex:380-420` | Standard service names derive from the local instance atom. Partition keys remain term-valued. |
| `lib/jido.ex:431-629` | Managed Agent lifecycle uses the Agent Dynamic Supervisor, local Registry, and public Runtime Store parent bindings. |
| `lib/jido/runtime_store.ex:1-23,57-78` | The instance owns a nondurable ETS table that survives Runtime Store worker restart. |
| `lib/jido/agent_server.ex:85-145` | Direct startup links to the caller. Managed startup uses the Agent Dynamic Supervisor. Managed children default to `:transient`; direct children default to `:temporary`. |
| `lib/jido/agent_server.ex:450-544` | Startup restores state, starts Plugin children, waits for readiness, and publishes ready only after readiness. It does not create revision zero. |
| `lib/jido/agent_server.ex:1244-1282` | Controlled termination stops execution, readiness, admission, Directive, error-policy, and Plugin runtime work. |
| `lib/jido/agent_server.ex:1325-1346` | Initial Plugin readiness uses `spawn_monitor/1`, not the instance Task Supervisor or an owner link. |
| `lib/jido/agent_server.ex:1370-1383` | Plugin admission runs as a task under the selected instance Task Supervisor. |
| `lib/jido/agent_server.ex:2572-2592` | Error-policy delivery uses an unlinked task, so abrupt Agent death does not directly stop it. |
| `lib/jido/agent_server/runtime_checkpoint.ex:8-50` | Same-instance abnormal restart restores the latest Agent and state version. Clean stop deletes that checkpoint. |
| `lib/jido/agent_server/plugin_lifecycle.ex:9-39,101-198` | Plugin runtime wrappers start in the Agent Dynamic Supervisor and register with instance-local names. |
| `lib/jido/agent_server/plugin_child.ex:49-70,79-183` | A wrapper links to its Agent Server, owns a private Supervisor, observes root restart, runs readiness, and stops with its owner. |
| `lib/jido/plugin.ex:915-927` | The current Plugin contract requires a permanent runtime root. |
| `lib/jido/plugin/init.ex:1-23` | Current Init has Agent Server PID, Agent ID, Plugin module, Jido instance, partition, and options, but no Plugin state or state version. |
| `lib/jido/agent_server/state.ex:28-37` | Parent, children, and unresolved spawn requests are private runtime state. |
| `lib/jido/agent_server/directive_runtime.ex:38-83,229-365` | Built-in child Directives support local and explicit known-node Agent ownership. |
| `lib/jido/agent_server/directive_runtime.ex:553-591` | Logical parent bindings use the instance Runtime Store. |
| `lib/jido/agent_server/child_placement.ex:8-65,93-160` | Target supervision owns child start and stop. Connection or timeout faults can be uncertain. There is no local fallback. |
| `lib/jido/agent_server/spawn_registry.ex:19-140` | Spawn receipts use generations, owner monitors, and Runtime Store recovery inside one instance lifetime. |
| `lib/jido/topology/controller.ex:1-24,62-70` | The Controller is a separate local Supervisor with its own task and resource supervisors. Public docs require application supervision after Jido. |
| `lib/jido/topology/controller/activation.ex:8-35` | The Controller starts temporary Agent Servers in the common Agent pool and waits for readiness. |
| `lib/jido/topology/controller/runtime.ex:193-325` | The Controller owns bounded activation passes, readiness state, and automatic or manual repair. |

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/supervisor_test.exs:4-53` | The instance and three visible standard services start, but strategy and failure coupling are not tested. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:70-150` | Execution work uses the instance Task Supervisor and stops after abrupt Agent death. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:152-326` | Plugin ownership, readiness gating, replacement, and same-instance checkpoint recovery are covered. |
| `test/jido/agent_server/child_lifecycle_test.exs:59-183,362-544` | Local child creation, addressing, stop, adoption, parent-death policy, and restarted-child tracking are covered. |
| `test/jido/agent_server/distributed_child_test.exs:41-399` | Known-node ownership, no fallback, indeterminate starts, closed generations, and failed stop retention are covered. |
| `test/jido/agent_server/remote_lifecycle_test.exs:9-100` | Remote exit and unreachable observations, disconnect cleanup, explicit replacement, and parent-node loss are covered. |
| `test/jido/agent_server/distributed_authority_test.exs:10-39` | Shared CAS can fence an older revision. Exclusive cluster ownership remains skipped and unproved. |
| `test/jido/topology/controller_test.exs:115-341` | Local activation, repair, cleanup, persistence restore, Bus repair, and Controller worker restart are covered. |
| `guides/deployment-and-shutdown.md:3-85` | Public guidance describes application ownership, same-instance restart, durable restart, local-only services, and safe effect recovery. |
| `examples/07_topology/README.md:15-98,163-200` | The application-supervised Controller and its static local repair boundary are documented and exercised. |

This documentation change inspected the tests and examples above. Runtime test
results are recorded under verification after the checks run for this seam.

## Retained baseline

- `RT-RB-001`: One application-owned Jido instance provides five named local
  runtime services under `:one_for_one`.
- `RT-RB-002`: Managed Agent Servers are direct peer children and default to
  `:transient`.
- `RT-RB-003`: Same-instance runtime checkpoints preserve the last nonpersistent
  commit across abnormal Server restart.
- `RT-RB-004`: Temporary Plugin wrappers share the Agent pool and stop a
  permanent internal Plugin root when their Agent Server stops.
- `RT-RB-005`: Runtime PIDs, monitors, timers, tasks, and child handles stay out
  of Agent state.
- `RT-RB-006`: Logical child relationships, parent-death policies, and parent
  bindings are current core behavior.
- `RT-RB-007`: Explicit known-node child ownership has no local fallback and can
  report indeterminate completion.
- `RT-RB-008`: Spawn request receipts survive a Spawn Registry worker restart,
  but not instance or VM loss.
- `RT-RB-009`: Static local Topology activation and repair use a separate
  Controller that the application supervises.
- `RT-RB-010`: Core has no distributed directory, election, lease, fencing,
  automatic failover, or exclusive cluster-owner contract.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `RT-GAP-001` | `RT-REQ-001` to `RT-REQ-007` | `lib/jido.ex:333-370`; supervisor tests | The five-child tree exists. Complete child-order and failure-coupling proof is missing. | `Retain`; add evidence |
| `RT-GAP-002` | `RT-REQ-008` to `RT-REQ-016` | Agent Server child spec and RuntimeCheckpoint | Placement and same-instance restart work. Instance-loss and persistent restart matrices are incomplete. | `Retain`; strengthen evidence |
| `RT-GAP-003` | `RT-REQ-017` to `RT-REQ-019` | Agent Server task and termination code | Execution ownership is strong. Initial readiness and error-policy delivery are not owner-linked for abrupt death. | `Change` worker ownership |
| `RT-GAP-004` | `RT-REQ-020` to `RT-REQ-023`, `RT-REQ-025` to `RT-REQ-027` | PluginLifecycle and PluginChild | Current wrapper placement and restart work. Full kill and failure-race coverage is incomplete. | `Retain`; strengthen evidence |
| `RT-GAP-005` | `RT-REQ-024` | Current Plugin Init and state-pull restart | Replacement gets fresh state after start, not one state-version input. | `Change`; blocked on seams 05 and 08 |
| `RT-GAP-006` | `RT-REQ-028` to `RT-REQ-032` | State, DirectiveRuntime, and child tests | Current logical relationship behavior is implemented. Public Ref identity is absent. | `Retain`; migrate handles later |
| `RT-GAP-007` | `RT-REQ-033` to `RT-REQ-044` | ChildPlacement, SpawnRegistry, and distributed tests | Known-node behavior is strong. Receipt storage is nondurable and gives no ownership transfer. | `Retain` bounded contract; `Defer` authority |
| `RT-GAP-008` | `RT-REQ-045` to `RT-REQ-047` | No core Agent Ref or namespace | Current child and facade paths use IDs and PIDs. | `Missing`; blocked on seams 03 and 09 |
| `RT-GAP-009` | `RT-REQ-048` | Core scope and distributed authority research test | The limit is documented. One skipped test shows exclusive ownership is absent. | `Retain` explicit non-guarantee |
| `RT-GAP-010` | `RT-REQ-049` to `RT-REQ-051` | Controller docs, code, and tests | The split exists, but old seam text mixed runtime and control-plane duties. | `Retain`; clarify owner boundary |
| `RT-GAP-011` | `RT-REQ-015`, `RT-REQ-025` | Persistence and Agent Server code | Revision-zero create is missing, and Plugin readiness can finish before any durable record exists. | `Blocked` on seams 07 and 08 |

## Disposition of superseded claims

This table accounts for the distinct claims in the removed runtime-topology,
remote-child, and gap-analysis files. Git history keeps their exact text.

| Superseded claim or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| Use Registry first, `:rest_for_one`, and separate Plugin and Agent pools. | `Replace`. | Seam 09 keeps the implemented five-child `:one_for_one` tree for first-stage V3. |
| Runtime Store and Spawn Registry are not first-class instance children. | `Reject`. | Both have current instance-scoped coordination contracts. |
| Agent Servers are direct peers and process one Turn at a time. | `Retain`. | Current code and seam 08 prove this model. |
| Core has no logical relationship store or public relationship API. | `Reject`. | Runtime Store parent bindings and `agent_parent_binding` are implemented and used by the Controller. |
| Core owns logical tags, adoption, child stop, delivery, and parent-death policy. | `Retain`. | Current Directives and tests depend on this contract. |
| Every owned task uses Task Supervisor and stops with its Server. | `Retain target; current gap`. | Initial readiness uses `spawn_monitor/1`, and error-policy delivery uses an unlinked task. |
| Nonpersistent abnormal restart resets to the initial Agent at version zero. | `Remove`. | Current code and prerequisite seams keep the latest same-instance checkpoint. |
| Persistent restart uses the latest durable record. | `Retain dependency`. | Seam 07 owns the record and seam 08 owns activation. |
| Instance restart discovers persistent Agents automatically. | `Reject`. | Activation requires an explicit child spec or control-plane decision. |
| Agent-to-Agent delivery is Ref-first now. | `Replace with additive target`. | Current child delivery uses tracked PIDs. Seams 03 and 09 must first add local Ref resolution. |
| A Plugin runtime always needs a process. | `Reject`. | Process-free owned Directive handling remains valid when no runtime is declared. |
| A separate `Jido.Plugin.Runtime` behavior with `dispatch/3` is the target. | `Remove`. | Seam 05 owns the facet migration and keeps current `Jido.Plugin` compatibility. |
| Plugin roots are normalized to `restart: :temporary`. | `Remove`. | Current and seam-05 contracts require a permanent root under a temporary wrapper. |
| A Plugin root gets no Agent Server PID and signals only through a Ref facade. | `Defer migration`. | Current Init has the Server PID. Exact future identity fields remain blocked in seam 05. |
| Plugin replacement must receive fresh complete state and version in Init. | `Retain target, narrow ownership`. | Seam 05 owns the bootstrap value; seams 08 and 10 own lifecycle and placement. |
| Add separate Plugin Runtime Init, Context, Status, and `plugin_runtimes` APIs. | `Remove as required`. | No such API exists. Current Plugin context and `children` inspection stay compatible. |
| Persistent first creation writes revision zero after Plugin readiness. | `Retain pending target`. | Seams 07 and 08 own this missing contract. |
| Add Plugin terminate and every-state-change callbacks. | `Reject`. | OTP shutdown and later Signals remain the selected boundaries. |
| Explicit remote `node:` selects an Erlang node and never falls back locally. | `Retain`. | This is implemented and tested. |
| A remote target owns the child process while the parent owns the logical link. | `Retain`. | This is the current ownership model. |
| Remote timeout or disconnect can be indeterminate after commit. | `Retain`. | Request identity resolves possible late acceptance without rolling back commit. |
| Retry identity uses generation and opaque reference; changed requests cannot replace pending ones. | `Retain`. | Current Agent Server and Spawn Registry implement it. |
| Closed Spawn Registry generations prevent late recreation and survive worker restart. | `Retain with limit`. | Records are nondurable and stop at instance loss. |
| Stop cannot silently discard an unresolved remote start. | `Retain`. | Current stop reports pending or failure and keeps tracking. |
| Remote child loss always proves process death. | `Reject`. | Distribution loss is reported as unreachable, not confirmed death. |
| Known-node placement includes distributed discovery, failover, leases, fencing, or exactly-once effects. | `Reject and defer`. | These need explicit external owners and contracts. |
| The static Controller is part of the Jido instance supervisor. | `Reject`. | It is an application-supervised peer and seam 11 owns it. |
| Runtime topology owns desired state, readiness policy, and repair passes. | `Move to seam 11`. | This seam owns component placement and lifecycle coupling only. |
| Deleted distributed results pages remain valid evidence links. | `Remove links`. | Those files are absent. Canonical tests and current guides replace them. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the formal plan only after the user approves this seam.

### Phase 0 — Resolve prerequisite and topology decisions

- Requirements: all `RT-REQ` identifiers.
- Required outcome: approve the first-stage tree, Plugin placement, checkpoint
  rule, relationship scope, remote limit, Ref integration, and control-plane
  split.
- Compatibility: no runtime change.
- Verification: review every `RT-DEC` item and blocker below.
- Exit criteria: each conflict has one approved owner and disposition.

### Phase 1 — Freeze the retained local topology

- Requirements: `RT-REQ-001` to `RT-REQ-017`, `RT-REQ-019` to `RT-REQ-023`,
  and `RT-REQ-025` to `RT-REQ-032` where current evidence applies.
- Required outcome: public docs and tests describe the five services, direct
  peers, restart sources, shutdown, Plugin wrappers, and relationships.
- Constraints: preserve all current ID, PID, partition, Plugin, child, and
  lifecycle APIs.
- Verification: child-order, kill-each-service, full-stop, Agent restart,
  Plugin restart, parent-death, and cleanup tests.
- Exit criteria: every retained coupling has direct fault-injection proof.

### Phase 2 — Close owned-work and Plugin replacement gaps

- Requirements: `RT-REQ-018`, `RT-REQ-024`, and `RT-REQ-025`.
- Required outcome: initial readiness and error-policy delivery stop on abrupt
  owner death, and each Plugin generation receives one committed state-version
  input.
- Constraints: seam 05 owns callback values; seam 08 owns Agent Server phases.
- Compatibility: keep current Plugin declarations and state-pull behavior until
  replacement parity passes.
- Verification: abrupt owner kill, first start, restart during commit, readiness
  failure, timeout, and stale-result tests.
- Exit criteria: no owned readiness work outlives its activation and no Plugin
  generation starts from mismatched state and version.

### Phase 3 — Add local Ref integration

- Requirements: `RT-REQ-045` to `RT-REQ-047`.
- Required outcome: resolve complete Refs to current local handles at each
  operation without implicit remote forwarding.
- Constraints: seams 03 and 09 own the Ref and facade. This seam adds no cluster
  directory.
- Compatibility: additive only; keep current ID and PID paths.
- Verification: replaced PID, wrong namespace, absent local handle, stale
  handle, and no-fallback tests.
- Exit criteria: identity stays stable while runtime handles change.

### Phase 4 — Prove bounded remote ownership

- Requirements: `RT-REQ-033` to `RT-REQ-044` and `RT-REQ-048`.
- Required outcome: all known-node request, stop, disconnect, late-result, and
  instance-loss cases match the bounded contract.
- Constraints: do not add automatic placement or exclusive authority.
- Compatibility: keep top-level `node:` syntax and current indeterminate
  meaning.
- Verification: distributed child, remote lifecycle, Spawn Registry restart,
  partition, and shared-CAS tests.
- Exit criteria: every result states what is confirmed, uncertain, or outside
  core.

### Phase 5 — Lock the control-plane handoff and release evidence

- Requirements: `RT-REQ-049` to `RT-REQ-051` and all approved requirements.
- Required outcome: seam 11 uses public runtime components and owns desired
  state, activation, readiness, repair, and cleanup.
- Compatibility: current static local Controller behavior remains supported.
- Verification: application supervision, Controller restart, manual and
  automatic repair, full shutdown, package checks, and dependent-doc review.
- Exit criteria: no runtime requirement defines live topology control or
  cluster policy.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `RT-REQ-001` to `RT-REQ-003` | `lib/jido.ex:346-370`; instance tests | Exact child inventory, strategy, order, and two-instance isolation test | `Partial` |
| `RT-REQ-004` and `RT-REQ-005` | Runtime Store code and worker-restart tests | Full instance stop and new-generation empty-store test | `Partial` |
| `RT-REQ-006` | Jido Task Supervisor config and topology scale example | Exact max-child scope test and documentation check | `Partial` |
| `RT-REQ-007` | OTP ownership and normal shutdown tests | Kill and controlled-stop matrix for all Dynamic Supervisor children | `Partial` |
| `RT-REQ-008` to `RT-REQ-011` | Agent Server start and child-spec code | Direct-peer and default-restart assertions | `Proven` for behavior; focused matrix is `Partial` |
| `RT-REQ-012` and `RT-REQ-013` | RuntimeCheckpoint and runtime lifecycle tests | Keep through Ref and Plugin migration | `Proven` |
| `RT-REQ-014` and `RT-REQ-016` | Runtime Store ownership and no discovery code | Complete instance restart with no implicit activation | `Partial` |
| `RT-REQ-015` | Persistent restore tests | Definition revision, initial record, instance restart, and error matrix | `Partial` |
| `RT-REQ-017` | Runtime lifecycle owned-execution tests | Admission and Directive placement matrix | `Proven` for execution; full set is `Partial` |
| `RT-REQ-018` | Controlled termination code | Abrupt kill during initial readiness, error-policy delivery, and every owned task type | `Conflict` for two worker types; otherwise `Partial` |
| `RT-REQ-019` | Active-turn tokens and late-result handling | Duplicate and late result tests for every task type | `Partial` |
| `RT-REQ-020` to `RT-REQ-023` | PluginLifecycle, PluginChild, and runtime lifecycle tests | Wrapper/root restart and owner-kill fault matrix | `Partial` |
| `RT-REQ-024` | Fresh-state pull after root restart | Atomic Plugin state-version bootstrap and commit-race tests | `Missing` |
| `RT-REQ-025` | Initial and replacement readiness failure paths | Full first-start, replacement, timeout, and cleanup matrix | `Partial` |
| `RT-REQ-026` | Current Plugin dispatch contract | Process-free facet parity test after seam-05 migration | `Partial` |
| `RT-REQ-027` | Agent state tests and private runtime structs | Recursive checkpoint handle-exclusion audit | `Proven` for current paths; target audit is `Partial` |
| `RT-REQ-028` to `RT-REQ-032` | Child lifecycle and restarted-child tests | Repeat with Ref migration and all parent policies across node loss | `Proven` locally; remote matrix is `Partial` |
| `RT-REQ-033` to `RT-REQ-042` | Distributed child and Spawn Registry tests | Controlled instance-loss and duplicate-after-loss tests | `Proven` for live instances; loss limit is `Partial` |
| `RT-REQ-043` and `RT-REQ-044` | Remote lifecycle tests | Reconnect and each parent-death policy matrix | `Partial` |
| `RT-REQ-045` to `RT-REQ-047` | Application research example only | Core Ref, namespace, replacement, absent, and no-fallback tests | `Missing` |
| `RT-REQ-048` | Core scope and skipped authority test | Architecture check and public non-guarantee review | `Partial` |
| `RT-REQ-049` to `RT-REQ-051` | Controller docs, code, examples, and tests | Application restart-coupling and public-only integration fixture | `Partial` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Instance tree | Keep five children and `:one_for_one`. Any strategy, order, or pool change needs a separate fault matrix and rollback rule. |
| Agent placement | Keep direct peer children and current restart options. Topology-controlled Agents remain temporary. |
| Runtime checkpoints | Keep same-instance last-commit recovery and clean-stop deletion. Do not convert it into a durability claim. |
| Persistence | Add revision-zero creation and all-write-error authority rules as one seams-07-and-08 rollout. |
| Plugin runtime | Keep the temporary wrapper and permanent root. Add state-version bootstrap without removing state-pull compatibility until parity passes. |
| Relationships | Keep built-in child Directives, private handles, parent policies, and parent-binding lookup. Add Ref use only after local resolution exists. |
| Remote placement | Keep top-level `node:` and no fallback. Preserve current uncertain-result and generation behavior. |
| Identity | Add Ref-first local paths. Keep ID, PID, name, partition, and direct Agent Server APIs. |
| Controller | Keep it outside the Jido instance. A later seam-11 change must preserve public runtime component contracts. |
| Cluster features | No migration exists because discovery, election, failover, leases, fencing, and exclusive ownership are not core features. |

Rollback of Plugin bootstrap must restore the old state-pull path and wrapper
behavior together. Rollback of durable startup must also restore record format,
write-error handling, caller errors, and activation behavior as one compatible
unit.

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `RT-BLK-001` | `Blocker` | 00 Overview and 90 Package boundaries | Local-core scope, static Topology, explicit known-node placement, and compatibility are pending approval. | Approve or change the Bright Line and package scope. |
| `RT-BLK-002` | `Blocker` | 12 Errors and contracts | Final runtime, timeout, not-found, and indeterminate error forms are pending. | Approve the error registry without changing runtime result meaning. |
| `RT-BLK-003` | `Blocker` | 03 Agent identity and 09 Jido instance | Core Agent Ref, namespace binding, partition conversion, and local Ref facade do not exist. | Approve and implement the additive local identity path. |
| `RT-BLK-004` | `Blocker` | 05 Plugins and 08 Agent Server | No current bootstrap value contains matching committed Plugin state and state version. | Approve the value, restart-race rule, and compatibility path. |
| `RT-BLK-005` | `Blocker` | 07 Persistence and 08 Agent Server | Revision-zero durable creation and all-write-error authority loss are not implemented. | Approve and align startup, failure, cleanup, and reactivation. |
| `RT-BLK-006` | `Assumption` | 09 Jido instance and 10 Runtime topology | The current five-child `:one_for_one` tree is the first-stage V3 target. | Approve or change `RT-DEC-001`. |
| `RT-BLK-007` | `Assumption` | 05 Plugins, 08 Agent Server, 10 Runtime topology | Temporary Plugin wrappers can remain peers in the Agent pool for V3. | Approve or change `RT-DEC-002` and `RT-DEC-003`. |
| `RT-BLK-008` | `Blocker` | 08 Agent Server, 10 Runtime topology | Initial readiness and error-policy delivery are not owner-linked for abrupt Agent death. | Select owner-bound mechanisms and prove cleanup. |
| `RT-BLK-009` | `Assumption` | Future cluster or application owner | Known-node placement stays separate from discovery and exclusive authority. | Define an external contract before any stronger claim. |
| `RT-BLK-010` | `Assumption` | 11 Topology control plane | The Controller remains application-supervised and owns one static local target and its repair. | Confirm in seam 11. |
| `RT-BLK-011` | `Blocker` | Design index and dependent seams | The main review table, seam 13, and seam 99 still link to removed runtime-topology files. The table also omits this seam's `design.md` and `alignment.md`. This task permits edits only in this folder. | Update those links in separately authorized owner-scoped edits. |

## Verification record

The following focused test runs passed on 2026-09-08:

```text
mix test test/jido/supervisor_test.exs \
  test/jido/agent_server/runtime_lifecycle_test.exs \
  test/jido/agent_server/child_lifecycle_test.exs \
  test/jido/agent_server/spawn_registry_test.exs \
  test/jido/topology/controller_test.exs --seed 0

55 passed

mix test test/jido/agent_server/distributed_child_test.exs \
  test/jido/agent_server/remote_lifecycle_test.exs \
  test/jido/agent_server/distributed_authority_test.exs \
  --include research --seed 0

19 passed, 1 skipped
```

The skipped test is the deferred exclusive cluster-owner requirement in
`distributed_authority_test.exs`.

## Completion criteria

- [ ] The user has approved or changed every `RT-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `RT-REQ` item has `Proven` evidence.
- [ ] No approved requirement has an unresolved `Conflict`, `Missing`, or
      `Blocked` state.
- [ ] Each standard instance child has restart and shutdown fault-injection
      evidence.
- [ ] Initial readiness, error-policy delivery, and all other Agent-owned work
      stop with the Agent Server.
- [ ] Every Plugin runtime generation receives one matching committed state and
      version.
- [ ] Local Ref resolution works without implicit Topology or transport
      fallback, and current handle APIs remain supported.
- [ ] Remote tests state confirmed, indeterminate, unreachable, and deferred
      authority outcomes separately.
- [ ] Seam 11 owns desired state and repair without private runtime access.
- [ ] Public docs, dependent seams, and the main design index use the approved
      three-file contract.
- [ ] After approval, a separate formal implementation plan defines tasks.
