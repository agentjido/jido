> Gap analysis. This document is pending approval.

# Runtime topology gap analysis

## Scope and owner

This report covers design seam 10. The seam owns the OTP runtime shape below
one Jido instance. It also owns Agent Server placement, owned runtime work,
logical child links, parent-death behavior, and explicit remote child ownership.

The code in `lib` is the source of truth for current behavior. The main runtime
topology document is a deferred proposal, not an implemented contract
(`docs/design/10_runtime-topology/runtime-topology.md:1-2`). The remote child
document is an implementation note with deferred extensions
(`docs/design/10_runtime-topology/remote-owned-children.md:1-7`).

Static topology definitions, desired state, readiness, and repair belong to
seam 11. This report covers them only where the current
`Jido.Topology.Controller` depends on seam 10.

## Implemented baseline

These items are current facts.

- A Jido instance uses a `:one_for_one` supervisor. Its children are a task
  supervisor, Registry, RuntimeStore, SpawnRegistry, and one Agent
  DynamicSupervisor (`lib/jido.ex:346-370`). There is no separate Plugin runtime
  pool.
- Each Agent Server is a direct child of the Agent DynamicSupervisor. Its
  default restart value is `:transient` when it has a Jido instance
  (`lib/jido/agent_server.ex:103-145`).
- Agent startup restores configured durable state when it exists. Without a
  persistence adapter, an abnormal restart restores the latest in-instance
  runtime checkpoint (`lib/jido/agent_server.ex:2874-2912`,
  `lib/jido/agent_server/runtime_checkpoint.ex:8-31`). A clean stop deletes that
  runtime checkpoint (`lib/jido/agent_server.ex:2954-2971`).
- Action, Flow, admission, and Directive work use the Jido task supervisor.
  The runtime links execution work to the Agent Server. The Server also stops
  tracked tasks during normal termination (`lib/jido/agent_server.ex:1256-1281`,
  `lib/jido/agent_server.ex:1370-1383`).
- A Plugin runtime uses `Jido.Plugin.Init`. This value contains the Agent Server
  PID, Agent ID, Plugin module, Jido instance, partition, and Plugin options
  (`lib/jido/plugin/init.ex:1-23`). It does not contain a complete Plugin state
  value or state version.
- A Plugin runtime wrapper is a temporary peer in the Agent DynamicSupervisor.
  The wrapper links to the Agent Server and starts a private one-child
  supervisor. The Plugin root must use `restart: :permanent`
  (`lib/jido/agent_server/plugin_lifecycle.ex:110-155`,
  `lib/jido/agent_server/plugin_child.ex:49-71`, `lib/jido/plugin.ex:915-927`).
  On an internal root restart, the runtime reads current Plugin state through
  `Jido.Plugin.state/2` and runs readiness again
  (`lib/jido/plugin.ex:268-274`, `lib/jido/agent_server/plugin_child.ex:89-145`).
- The Agent Server keeps logical parent and child data in private runtime state.
  It also writes parent bindings to the instance RuntimeStore and exposes
  `Jido.agent_parent_binding/3` (`lib/jido/agent_server/state.ex:28-37`,
  `lib/jido/agent_server/directive_runtime.ex:553-591`, `lib/jido.ex:601-629`).
- `SpawnAgent`, `AdoptChild`, `StopChild`, `EmitToChild`, and `EmitToParent` are
  implemented core Directives (`lib/jido/agent/directive.ex:17-48`,
  `lib/jido/agent_server/directive_runtime.ex:38-83`).
- Explicit remote placement uses an Erlang node. It does not fall back to local
  placement. The target instance starts and supervises the child. The parent
  keeps the logical link (`lib/jido/agent_server/directive_runtime.ex:229-365`,
  `lib/jido/agent_server/child_placement.ex:8-43`).
- Remote creation uses a generation and reference. A timeout or lost connection
  produces an uncertain result. SpawnRegistry stores the newest request state
  in RuntimeStore, closes stopped requests, and restores its state after its own
  process restart (`lib/jido/agent_server/directive_runtime.ex:307-349`,
  `lib/jido/agent_server/child_placement.ex:149-160`,
  `lib/jido/agent_server/spawn_registry.ex:19-79`).
- The current static topology controller is outside the Jido instance
  supervisor. Its public documentation tells the application to supervise it
  after Jido with `:rest_for_one` (`lib/jido/topology/controller.ex:1-23`). It
  starts temporary Agents in the common Agent pool, waits for Agent readiness,
  binds logical parents, and repeats repair passes
  (`lib/jido/topology/controller/activation.ex:8-35`,
  `lib/jido/topology/controller/runtime.ex:193-325`,
  `lib/jido/topology/controller/runtime.ex:360-397`).

## Aligned contracts

These items in the design agree with current behavior.

- Agent Servers are peers in one DynamicSupervisor. One Server processes one
  Turn at a time (`docs/design/10_runtime-topology/runtime-topology.md:31-34`,
  `lib/jido.ex:363-367`, `guides/agent-server-lifecycle.md:16-21`).
- Plugin readiness gates successful Agent startup. Failed Plugin startup stops
  the Server and its provisional Plugin children
  (`docs/design/10_runtime-topology/runtime-topology.md:142-146`,
  `lib/jido/agent_server.ex:506-575`).
- Plugin Directive work runs after the Agent commit. A Plugin does not need a
  runtime process for Directive dispatch (`docs/design/10_runtime-topology/runtime-topology.md:89-92`,
  `lib/jido/plugin.ex:20-24`, `guides/plugin-contract-and-lifecycle.md:50-61`).
- Required execution and Directive work is bounded and owned. Tests show that
  Agent death stops execution work and that a supervised stop stops Directive
  work (`test/jido/agent_server/runtime_lifecycle_test.exs:70-97`,
  `test/jido/agent_server/runtime_lifecycle_test.exs:133-150`,
  `test/jido/agent_server/directive_execution_test.exs:225-235`).
- Child Directives keep runtime references out of Agent state. Tests cover
  spawn, send, reply, stop, adoption, parent-death policy, and restarted child
  PID tracking (`test/jido/agent_server/child_lifecycle_test.exs:59-106`,
  `test/jido/agent_server/child_lifecycle_test.exs:108-183`,
  `test/jido/agent_server/child_lifecycle_test.exs:362-544`).
- The remote ownership note agrees with the code for explicit placement,
  target-node process ownership, no local fallback, uncertain starts, request
  identity, stop behavior, and parent-death handling
  (`docs/design/10_runtime-topology/remote-owned-children.md:9-63`). Focused
  distributed tests cover these contracts
  (`test/jido/agent_server/distributed_child_test.exs:41-76`,
  `test/jido/agent_server/distributed_child_test.exs:120-168`,
  `test/jido/agent_server/distributed_child_test.exs:210-396`).
- The current topology controller implements local activation, readiness,
  repair, identity checks, and cleanup. Its tests cover Agent repair, parent
  binding repair, Bus repair, state retention, and controller worker restart
  (`test/jido/topology/controller_test.exs:115-168`,
  `test/jido/topology/controller_test.exs:251-341`).

## Gaps

### Missing implementation

These proposed contracts have no matching implementation.

1. The proposed Jido shape has `:rest_for_one`, Registry first, a separate
   Plugin runtime pool, and the Agent pool last
   (`docs/design/10_runtime-topology/runtime-topology.md:12-29`). Current code
   has a different child order, `:one_for_one`, RuntimeStore and SpawnRegistry,
   and no Plugin pool (`lib/jido.ex:357-370`).
2. The proposed `Jido.Plugin.Runtime` behavior and its `Init`, `Context`, and
   `Status` types do not exist. There is no `plugin_runtimes/2` instance API
   (`docs/design/10_runtime-topology/runtime-topology.md:98-122`,
   `docs/design/10_runtime-topology/runtime-topology.md:124-220`). Current code
   uses `Jido.Plugin`, `Jido.Plugin.Init`, and `Jido.Plugin.DirectiveContext`
   (`lib/jido/plugin.ex:43-102`, `lib/jido/plugin/init.ex:1-23`,
   `lib/jido/plugin/directive_context.ex:1-36`).
3. The proposal requires the Agent Server to create a fresh complete Init for
   each Plugin runtime replacement. Current OTP restart reuses the original
   child specification and Init. The runtime must fetch current Plugin state
   through the Agent Server (`docs/design/10_runtime-topology/runtime-topology.md:148-157`,
   `lib/jido/agent_server/plugin_child.ex:49-54`,
   `lib/jido/agent_server/plugin_child.ex:89-145`).
4. The proposal requires a persistent first creation to write an initial Record
   only after all Plugin runtimes are ready. Current bootstrap performs no
   persistence write. The first write occurs on a successful Turn commit or a
   clean stop (`docs/design/10_runtime-topology/runtime-topology.md:142-146`,
   `lib/jido/agent_server.ex:506-544`, `lib/jido/agent_server.ex:2907-2949`).
5. Plugin startup readiness uses `spawn_monitor/1`, not the Jido task
   supervisor (`lib/jido/agent_server.ex:1325-1336`). The child does not monitor
   or link to the owner. Normal termination stops it, but an untrappable Agent
   kill can bypass that cleanup. Thus the design rule that every readiness task
   stops with its owner is not fully implemented
   (`docs/design/10_runtime-topology/runtime-topology.md:36-39`).
6. The design uses an Agent Ref as the location-independent Signal target
   (`docs/design/10_runtime-topology/runtime-topology.md:54-62`). The current
   child dispatch path keeps a PID in `ChildInfo` and dispatches to the PID that
   is in current Server state (`lib/jido/agent_server/directive_runtime.ex:155-167`).
   Stable Ref resolution is not implemented in this seam.

### Design and code conflict

These are direct conflicts between current facts and design text.

1. The design says that core has no logical relationship store or relationship
   API (`docs/design/10_runtime-topology/runtime-topology.md:31-34`,
   `docs/design/10_runtime-topology/runtime-topology.md:224-226`). The same
   design later says that core owns logical relationships
   (`docs/design/10_runtime-topology/runtime-topology.md:64-74`). Current code
   has both a RuntimeStore record and a public lookup API
   (`lib/jido/agent_server/directive_runtime.ex:553-591`, `lib/jido.ex:601-629`).
2. The design says that a nonpersistent abnormal restart resets to the complete
   initial Agent and state version zero
   (`docs/design/10_runtime-topology/runtime-topology.md:41-48`). Current code
   restores the latest in-instance runtime checkpoint and version. The public
   lifecycle guide documents current code behavior
   (`lib/jido/agent_server/runtime_checkpoint.ex:8-31`,
   `guides/agent-server-lifecycle.md:41-48`).
3. The design requires a temporary Plugin root that cannot restart from old
   input (`docs/design/10_runtime-topology/runtime-topology.md:120-122`). Current
   public Plugin contract requires a permanent root. Its wrapper is temporary
   (`lib/jido/plugin.ex:5-11`, `lib/jido/agent_server/plugin_lifecycle.ex:114-121`).
4. The design says that the Plugin root does not receive the Agent Server PID
   (`docs/design/10_runtime-topology/runtime-topology.md:159-162`). Current
   `Jido.Plugin.Init` requires that PID and exposes `Jido.Plugin.state/2` through
   it (`lib/jido/plugin/init.ex:4-13`, `lib/jido/plugin.ex:268-274`).
5. The proposal names `dispatch/3` on a separate runtime module. Current public
   contract uses `dispatch/4` on the Plugin module and passes static Plugin
   options as the fourth argument (`docs/design/10_runtime-topology/runtime-topology.md:98-118`,
   `lib/jido/plugin.ex:82-102`, `lib/jido/plugin.ex:317-326`).
6. The proposal puts Plugin state and version in the replacement Init. Current
   Init has neither value. Current `DirectiveContext` has committed Plugin state
   and version, but it uses Agent ID and complete Signal values instead of the
   proposed Ref and Signal coordinates (`docs/design/10_runtime-topology/runtime-topology.md:124-189`,
   `lib/jido/plugin/init.ex:4-13`, `lib/jido/plugin/directive_context.ex:10-26`).

### Missing decision

These points need an explicit design decision before implementation work.

1. Select the canonical Jido supervision shape. Decide if Registry failure must
   restart all later runtime owners. Also decide if RuntimeStore and
   SpawnRegistry remain first-class instance children.
2. Select one Plugin runtime lifecycle. The choices are the current permanent
   root with state lookup, or the proposed temporary root with a fresh complete
   Init. Do not support both as implicit variants.
3. Select nonpersistent restart semantics. Decide if an in-instance checkpoint
   is part of the supported contract or if abnormal restart must reset to
   version zero.
4. Define persistent creation semantics. Decide if activation creates revision
   zero, and define the atomic boundary between readiness and that first write.
5. Resolve the relationship-store contradiction. The current topology
   controller and restarted-child binding recovery depend on the RuntimeStore
   record (`lib/jido/topology/controller/runtime.ex:390-397`,
   `test/jido/agent_server/child_lifecycle_test.exs:510-544`).
6. Keep local topology activation and repair in seam 11, or explicitly move a
   named part into seam 10. Current public scope says that core supports bounded
   local activation, readiness, repair, and cleanup, but not placement or live
   target changes (`guides/core-scope.md:7-22`, `guides/core-scope.md:53-89`).
7. Keep automatic placement, failover, leases, fencing, and cluster authority
   outside core, or define a new owner. The remote note correctly marks these as
   deferred (`docs/design/10_runtime-topology/remote-owned-children.md:65-77`).

### Missing verification

These are verification gaps for current or proposed behavior.

1. Supervisor tests check that the main children exist, but they do not test
   child order, supervisor strategy, Registry failure, RuntimeStore failure, or
   the required restart cascade (`test/jido/supervisor_test.exs:23-52`).
2. No focused test proves that Plugin startup readiness work stops after an
   abrupt Agent Server kill. Current tests prove readiness gating and normal
   runtime replacement, but not this owner-death case
   (`test/jido/agent_server/runtime_lifecycle_test.exs:174-194`,
   `test/jido/agent_server/runtime_lifecycle_test.exs:225-291`).
3. No test can verify the proposed fresh Init, temporary-root rule, runtime
   Status API, or Ref-first Plugin Signal API because these contracts are absent.
4. There is no focused test for a persistent first activation that proves both
   revision-zero creation and cleanup after readiness failure. Current
   persistence tests start at explicit saves or Turn commits
   (`test/jido/persistence_test.exs:186-205`,
   `test/jido/persistence_test.exs:259-279`).
5. Local and remote child tests are strong for known-node ownership. They do not
   prove partition recovery, node replacement authority, fencing, or failover.
   The design correctly assigns those cases to DIST-02 and DIST-03
   (`docs/design/10_runtime-topology/remote-owned-children.md:74-77`).
6. The local topology controller tests verify repair on one node. They do not
   verify cross-node placement or ownership transfer. Current public module
   documentation says that these features are not supported
   (`lib/jido/topology/controller.ex:12-23`).

## Narrow dependency notes

These are current dependency facts. They are not proposals.

- Seam 03 must define stable Agent identity before seam 10 can replace tracked
  PIDs with Ref-first resolution.
- Seams 06 and 07 define commit, persistence, and durability rules. Seam 10
  must use those rules for revision-zero creation, abnormal restart, and remote
  indeterminate outcomes.
- Seam 08 owns Agent Server phases, task cancellation, readiness, and public
  status. Seam 10 owns where those processes run and who stops them.
- Seam 09 owns the Jido instance facade and instance supervisor. Its public
  names and child APIs expose the runtime topology.
- Seam 05 owns the Plugin callback contract and portable Plugin state. A change
  to Init or replacement behavior is a coordinated seam 05 and seam 10 change.
- Seam 11 owns the current topology Controller. It uses the common Agent pool,
  `AgentServer.await_ready/2`, adoption, RuntimeStore parent bindings, and
  temporary Agent restart specifications.
- Seam 12 owns structured error and Outcome contracts such as
  `child_spawn_indeterminate`. Seam 13 observes these lifecycle events.

## Ordered recommendations

These items are proposals, not current facts.

1. Lock the current-versus-proposed decisions first: Jido supervisor shape,
   Plugin runtime lifecycle, nonpersistent restart semantics, initial durable
   creation, and relationship storage.
2. Update `runtime-topology.md` to describe only the selected contracts. Move
   rejected alternatives to a short rationale section. Remove the internal
   relationship-store contradiction.
3. If the current Plugin model wins, replace the proposed
   `Jido.Plugin.Runtime.*` API with the implemented `Jido.Plugin` contract. If
   the proposed model wins, implement it as one coordinated seam 05 and seam 10
   change before public documentation changes.
4. Fix Plugin startup readiness ownership. Run readiness in an owner-bound task,
   or make the readiness process monitor its Agent Server and stop on owner
   death. Add the abrupt-kill test at the same time.
5. Add supervisor fault tests for the selected strategy and child order. Test
   Registry, RuntimeStore, SpawnRegistry, Agent pool, and Plugin runtime failure
   effects.
6. Add persistent creation tests for readiness success, readiness failure,
   revision zero, and no partial record. Then implement the selected write
   boundary if the tests expose a gap.
7. Keep the known-node remote contract as the supported core boundary. Preserve
   the existing distributed tests. Put partition recovery, fencing, and owner
   replacement in the later authority design.
8. Keep topology activation and repair analysis in seam 11. In seam 10, state
   only the runtime services and ownership guarantees that the Controller uses.

## Verification performed for this report

The following focused test runs passed on 2026-09-08.

```text
mix test test/jido/supervisor_test.exs \
  test/jido/agent_server/runtime_lifecycle_test.exs \
  test/jido/agent_server/child_lifecycle_test.exs \
  test/jido/agent_server/spawn_registry_test.exs \
  test/jido/topology/controller_test.exs --seed 0

55 tests, 0 failures

mix test test/jido/agent_server/distributed_child_test.exs --seed 0

14 tests, 0 failures
```
