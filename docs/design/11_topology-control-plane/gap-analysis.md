# Topology control-plane gap analysis

> Review result for the current `v3-spike` code. This report separates current
> facts from proposed work. It does not make the deferred design a current API.

## Scope and owner

This review covers only the topology control-plane seam. The seam owns Topology
authoring, validated instances and plans, desired-state authority, local
reconciliation, readiness, repair, and live upgrades. It does not own the full
OTP runtime topology, cluster placement, or durable work distribution.

Current code has two owners with different scopes:

- `Jido.Topology` owns static definitions, pure instantiation, and plan
  construction.
- `Jido.Topology.Controller` owns one fixed live target and repairs the local
  processes for that target.

The proposed design changes the live authority. One owner Agent will own the
durable desired input. A Topology Plugin runtime under that Agent will own the
controller. This owner runtime does not exist in current code.

## Implemented baseline

The following items are current facts.

1. A Topology module is one combined Spark host. `Jido.Topology.__using__/1`
   selects the internal Topology host for `Jido.Agent`, and that host loads the
   Agent and Topology DSL extensions. The Agent and Topology compilers read the
   same Spark data (`lib/jido/topology.ex:45-79`,
   `lib/jido/agent.ex:137-180`,
   `lib/jido/topology/dsl/extension.ex:207-227`).
2. The module exposes an owner Agent definition through `owner/0` and an owner
   Agent constructor through `new_agent/1`. Its `new/1` still creates a
   `%Jido.Topology.Instance{}` (`lib/jido/topology.ex:54-78`).
3. `Jido.Topology.instantiate/2` validates the static definition, instance ID,
   portable input, composition, and plan. It starts no process
   (`lib/jido/topology.ex:82-109`).
4. The current definition, instance, and plan have no owner field. An instance
   holds `id`, `definition`, `input`, and `plan`. A plan holds child Agents,
   resources, dependency layers, lookup data, and component counts
   (`lib/jido/topology.ex:20-40`,
   `lib/jido/topology/instance.ex:4-12`,
   `lib/jido/topology/plan.ex:7-16`).
5. Codec version 2 stores static Topology data. It does not store input, plans,
   PIDs, Agent state, or runtime status. It also does not store an owner Agent
   (`lib/jido/topology/codec.ex:1-17`,
   `lib/jido/topology/codec.ex:25-76`).
6. The Controller accepts one `%Jido.Topology.Instance{}`. It validates the
   instance again and puts it in fixed runtime state. `reconcile/2` requests a
   new pass against that same target (`lib/jido/topology/controller.ex:31-70`,
   `lib/jido/topology/controller.ex:81-90`,
   `lib/jido/topology/controller/runtime.ex:13-31`,
   `lib/jido/topology/controller/runtime.ex:184-205`).
7. Current reconciliation starts missing Agents and Buses, checks logical
   ownership, restores child Agent state through the configured persistence
   adapter, and repairs failed members. Healthy owned Agents keep their PID and
   state (`lib/jido/topology/controller/runtime.ex:328-427`,
   `lib/jido/topology/controller/activation.ex:8-56`).
8. The current readiness policy is only `:all`. Controller startup returns
   before readiness. `await_ready/2` waits for all planned resources, Agents,
   and ownership bindings (`lib/jido/topology/validation.ex:140-159`,
   `lib/jido/topology/controller.ex:43-79`).
9. Normal Controller shutdown stops owned Agents in reverse dependency order.
   Buses are children of the Controller resource supervisor
   (`lib/jido/topology/controller/runtime.ex:149-179`,
   `lib/jido/topology/controller.ex:62-70`).
10. There is no public `Jido.start_topology` function. The current public live
    API starts an Agent or starts a Controller directly
    (`lib/jido.ex:458-485`, `lib/jido/topology/controller.ex:43-60`).

## Aligned contracts

These parts of the design agree with current code and tests.

- One Topology module can contain the normal `agent`, `routes`, and nested
  `topology` blocks. A missing `agent` block creates a neutral owner definition
  (`test/jido/topology/authoring_host_test.exs:79-172`).
- Additional extensions are sent only to the lowering pass that they implement.
  An extension that implements neither callback is rejected
  (`lib/jido/agent/dsl/compiler.ex:13-18`,
  `lib/jido/topology/dsl/compiler.ex:9-16`,
  `lib/jido/topology/dsl/compiler.ex:231-249`).
- Nested Topology sections and old top-level sections are both accepted during
  migration. One section cannot use both locations
  (`lib/jido/topology/dsl/compiler.ex:159-179`,
  `test/jido/topology/authoring_host_test.exs:224-274`).
- The constructor collision has a working compatibility rule. `new/1` creates a
  Topology instance, `new_agent/1` creates an Agent, and Agent Server startup
  uses `__agent_config__/0` before a generic module `new/1`
  (`lib/jido/topology.ex:58-78`,
  `lib/jido/agent_server/options.ex:184-199`,
  `test/jido/topology/authoring_host_test.exs:124-142`).
- The public Controller documentation clearly says that repair uses the
  existing target and is not a target update
  (`lib/jido/topology/controller.ex:81-90`).
- Current tests verify startup, readiness, ownership, identity conflicts,
  cleanup, automatic repair, manual repair, child restore, and Bus repair
  (`test/jido/topology/controller_test.exs:9-37`,
  `test/jido/topology/controller_test.exs:115-168`,
  `test/jido/topology/controller_test.exs:247-340`,
  `test/examples/07_topology/07_01_independent/independent_test.exs:21-44`).

## Gaps

### Missing implementation

These items are proposals. Current code does not implement them.

1. **Canonical owner data.** `Jido.Topology`, `Instance`, and `Plan` do not have
   the proposed owner fields. The Builder and Codec cannot build or encode
   those fields. Codec version 3 and the version 1 or 2 migration rule do not
   exist.
2. **Durable desired state.** There is no `Jido.Topology.Plugin`, reserved
   Topology state field, Topology Directive family, state reducer, or Topology
   Plugin runtime. No committed owner state contains the desired input or a
   definition revision.
3. **Owner startup API.** There is no `Jido.start_topology` API and no generated
   Jido instance wrapper. There is no bootstrap Signal that commits desired
   state before the first child starts. There is no startup path that waits for
   reconciliation and returns the owner PID.
4. **Replaceable controller target.** The Controller cannot accept a new
   instance or state version. It cannot diff the new target against observed
   members. It cannot stop removed members or replace changed members while it
   keeps unchanged members.
5. **Revision control.** Controller status does not report desired and last
   reconciled owner state versions. The Controller cannot reject a stale
   version or supersede an active pass with one later target.
6. **Live resource changes.** No update path changes Buses, subscriptions,
   ownership bindings, dependency layers, or included component plans. The
   research diff covers Agents only and does not apply changes
   (`examples/99_research/99_16_topology_upgrade/topology_upgrade.ex:32-67`).
7. **Upgrade and rollback operations.** There is no public definition upgrade,
   rolling update, rollback, or target validation operation. Full Controller
   replacement is the only demonstrated way to apply a new target. It replaces
   every child PID (`test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs:55-78`).

### Design/code conflict

The design is marked as deferred, so these conflicts do not mean that current
code violates a current public contract. They show where implementation must
change before the proposal can become the contract.

1. **Live authority.** Current code makes the directly supervised Controller
   the authority for a fixed `%Instance{}`. The proposal makes the owner Agent's
   committed Plugin state the only desired-state authority.
2. **Runtime ownership.** Current application code owns the Controller as a
   sibling after the Jido instance. The proposal puts the Controller under an
   owner Agent Plugin runtime (`lib/jido/topology/controller.ex:3-10`).
3. **Public handle.** Current callers hold a Controller PID. The proposed API
   returns the owner Agent PID and treats Controller PIDs as observation data.
4. **Start completion.** Current `Controller.start_link/1` returns before the
   Topology is ready. The proposed `start_topology` returns only after its
   readiness policy succeeds.
5. **Desired data location.** Current runtime state holds the complete static
   definition, input, and plan in `%Instance{}`. The proposal keeps only
   portable input and revision coordinates in committed owner state, and
   rebuilds the plan outside Agent state.
6. **Document shape.** Current Codec version 2 has no owner. The proposal adds a
   static owner and therefore requires a new document shape and migration.

### Missing decision

The design must settle these points before implementation.

1. **Definition revision resolution.** Define who assigns
   `definition_revision`, how a runtime resolves it to exact code and static
   data, and what happens when old code is no longer loaded. Input plus an
   integer is not enough to reproduce an old target after a deployment.
2. **Upgrade identity.** Define whether a module rename, Agent module change,
   Plugin change, route change, schema change, initial-state change, Bus option
   change, connection change, or relationship change is an unchanged member, a
   restart, or a migration.
3. **Partial failure policy.** Define the observable state after some additions
   start and a later addition fails. State whether the controller keeps partial
   progress, retries it, or rolls it back.
4. **Operation terms.** Define repair, resize, definition upgrade, rolling
   update, and rollback as separate operations. Specify the allowed input and
   the completion result for each operation.
5. **Rollout order.** Define the order for additions, changed members, and
   removals. Define when old members stop, how dependencies stay available, and
   whether changed members can run at the same time.
6. **Revision supersession.** Define whether one later desired version cancels
   active tasks, waits for them, or lets them finish before one follow-up pass.
   Define how the runtime handles skipped versions.
7. **Restore behavior through `start_agent`.** The proposal says that
   `start_agent` starts only the owner. It also says that a restored owner can
   restart reconciliation from committed desired state. State this difference
   as an explicit new-owner and restored-owner contract.
8. **Reserved state ownership.** Select the Topology Plugin state key and define
   compile-time conflict checks with owner domain state and other Plugins.
9. **Startup failure and identity collision.** Define cleanup and retry behavior
   when owner startup succeeds but bootstrap, reconciliation, or readiness
   fails. Define idempotency for a repeated `start_topology` request.
10. **Readiness during upgrade.** The current policy accepts only `:all`. Define
    whether upgrade readiness needs minimum capacity, component readiness, or
    another policy before rolling work is implemented.
11. **Rollback source.** Define whether rollback selects a saved desired-state
    revision, a saved static document, or an application-supplied target. Define
    how rollback interacts with child state that a newer definition wrote.

### Missing verification

The current focused test run completed with 99 passing tests and one skipped
test:

```text
mix test test/jido/topology \
  test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs \
  --include example --seed 0

99 passed, 1 skipped
```

The skipped test is the direct evidence for the live-update gap. It tries to
submit a larger target through `Controller.start_link/1`, but the existing
controller identity makes that call return `already_started`
(`test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs:80-97`).

The owner runtime needs focused tests for these contracts:

- initial desired state persists before any child starts;
- a failed owner persistence write starts no child work;
- post-commit reconciliation failure does not undo the owner commit;
- Plugin runtime restart reads committed desired state and state version;
- growth, shrink, and definition change keep unchanged PIDs and state;
- removed Agents and Buses stop in safe reverse dependency order;
- changed subscriptions and ownership bindings converge without duplicate
  ownership;
- stale and superseded revisions cannot replace a newer target;
- one included Topology does not start a second owner;
- owner shutdown stops the Controller, Buses, and owned Agents;
- owner, child, and Bus identity conflicts do not stop unrelated processes;
- upgrade failure, retry, and rollback follow the selected policy; and
- Codec migration gives old documents the selected default owner.

## Narrow dependency notes

These dependencies directly affect this seam. They do not expand the scope of
this review.

- **Agent authoring.** The combined host depends on the Agent compiler and its
  extension filter. Any owner field or built-in Plugin injection must keep the
  current constructor and extension behavior
  (`lib/jido/agent.ex:137-180`, `lib/jido/agent/dsl/compiler.ex:7-58`).
- **Agent Server commit.** The proposed durability order can use current
  behavior. The Server persists first, then installs the new Agent and state
  version, replies to the caller, and schedules Directive work
  (`lib/jido/agent_server.ex:1493-1545`). Plugin Directive context includes the
  committed state version and Plugin state
  (`lib/jido/agent_server.ex:1785-1817`).
- **Plugin runtime.** Sensor Manager and Scheduler show useful local patterns:
  portable desired state, post-commit reconcile, runtime restore, retry, and
  stale-version checks (`lib/jido/plugin/sensor_manager.ex:23-82`,
  `lib/jido/plugin/sensor_manager/runtime/controller.ex:15-63`,
  `lib/jido/plugin/scheduler/runtime.ex:67-90`,
  `lib/jido/plugin/scheduler/runtime.ex:526-530`). These patterns are evidence,
  not a complete Topology update protocol.
- **Jido instance.** `Jido.start_topology` and the generated instance wrapper
  must use the existing Agent pool, Registry, persistence configuration, and
  identity rules. They must not create a second live namespace
  (`lib/jido.ex:144-160`, `lib/jido.ex:473-485`).
- **Runtime topology and persistence.** Child Agent restore already uses the
  Jido persistence adapter. Owner desired-state durability depends on the Agent
  Server compare-and-swap commit. Cluster placement and durable work ownership
  remain outside this seam.

## Ordered recommendations

The following items are proposals, in implementation order.

1. Lock the missing decisions for revision resolution, diff identity, partial
   failure, rollout order, restore behavior, and rollback. Do this before a
   public update API is added.
2. Add the canonical owner fields to `Jido.Topology`, `Instance`, and `Plan`.
   Update Builder and Codec together. Add a new Codec version and explicit old
   document migration tests.
3. Add the built-in Topology Plugin. Keep only validated desired input and exact
   revision coordinates in its state. Add compile-time protection for its
   reserved state key.
4. Add typed desired-state Directives and pure Plugin state reduction. Prove
   that failed persistence causes no runtime reconciliation.
5. Move Controller ownership under the Plugin runtime. Add a versioned target
   update call and status fields for desired and last reconciled versions.
6. Implement a full plan diff for Agents, Buses, subscriptions, relationships,
   layers, and included components. Keep unchanged members. Apply additions,
   changes, and removals in the selected safe order.
7. Add `Jido.start_topology` and the Jido instance wrapper. Use the normal owner
   Agent startup and one committed bootstrap Turn. Return the owner PID only
   after the selected readiness condition succeeds.
8. Add the missing failure, restart, update, and rollback tests. Remove the
   research test skip only when the public live-update path passes it.
9. Update the public guides and examples after the owner path has behavior equal
   to or better than direct Controller startup. Keep the direct Controller API
   clearly marked until its compatibility policy is final.

## Evidence summary

- Design target: `docs/design/11_topology-control-plane/topology-authoring-host.md:10-31`,
  `docs/design/11_topology-control-plane/topology-authoring-host.md:155-235`,
  `docs/design/11_topology-control-plane/topology-authoring-host.md:238-303`.
- Static unit and pending runtime unit:
  `docs/design/11_topology-control-plane/topology-authoring-host.md:305-334`.
- Current supported Topology scope and explicit upgrade deferral:
  `guides/core-scope.md:7-18`, `guides/core-scope.md:53-101`.
- Current authoring and data shapes: `lib/jido/topology.ex:20-109`,
  `lib/jido/topology/instance.ex:1-15`, `lib/jido/topology/plan.ex:1-70`.
- Current fixed-target runtime: `lib/jido/topology/controller.ex:1-90`,
  `lib/jido/topology/controller/runtime.ex:13-81`,
  `lib/jido/topology/controller/runtime.ex:184-205`.
- Current repair and activation behavior:
  `lib/jido/topology/controller/runtime.ex:207-326`,
  `lib/jido/topology/controller/runtime.ex:347-447`,
  `lib/jido/topology/controller/activation.ex:8-89`.
- Upgrade evidence:
  `examples/99_research/99_16_topology_upgrade/topology_upgrade.ex:32-67`,
  `test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs:13-97`.
