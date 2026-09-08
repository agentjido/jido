> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../../guides/core-scope.md).

# Topology as one Agent authoring host

- Status: Static authoring prototype implemented; owner runtime design pending
- Scope: Topology DSL composition, owner Agent identity, construction, startup,
  persistence, and reconciliation

## Decision

`use Jido.Topology` is the only authoring host for one topology module. It loads
one Spark DSL that contains the normal Agent sections and the Topology sections.
It does not ask an application to add `Jido.Topology.DSL` as an Agent extension.
It does not ask an application to define a second owner module.

The module has three sibling blocks:

- `agent do ... end` configures the one owner Agent.
- `routes do ... end` is the normal v3 Agent routing DSL.
- `topology do ... end` contains the static owned graph and startup policy.

An omitted `agent` block produces a neutral owner with the topology name, an
empty domain schema, no Plugins, no routes, and empty metadata.

The static authoring part is sound against the current compiler. The runtime is
not yet sound if Core only starts the current `Jido.Topology.Controller`. That
controller owns a fixed instance target in process state. It does not get its
target from committed owner Agent state. A direct `start_topology` wrapper over
the current controller would therefore create a second desired-state authority.
Do not add that wrapper until the owner Plugin contract below exists.

## Public DSL

```elixir
defmodule MyApp.SupportTeam do
  use Jido.Topology,
    name: "support_team",
    extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             worker_count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(3),
             open_cases: Zoi.integer() |> Zoi.default(0)
           })

    ai :coordinator do
      model "anthropic:claude-sonnet-4-5"
      instructions "Coordinate the support team."
    end
  end

  routes do
    signal_source "/support-team"

    route "support.request", ai: :coordinator do
      define :request, args: [:message]
    end

    route "support.resize", MyApp.ResizeTeam do
      define :resize, args: [:worker_count]
    end
  end

  topology do
    agents do
      agent :triage, MyApp.TriageAgent

      group :workers, MyApp.SupportAgent do
        count input(:worker_count)
      end
    end

    resources do
      bus :events
    end

    relationships do
      owns :triage, :workers
    end

    connections do
      subscribe :workers, to: :events, path: "support.**"
    end

    topologies do
      include :audit, MyApp.AuditTopology
    end

    startup do
      concurrency 8
      ready :all
    end
  end
end
```

The nested Topology sections keep the existing entity names and compilers. This
is less risky than a flat `topology` block because `agent`, `bus`, and export or
import names have different meanings in different sections. During the beta
migration, the existing top-level `agents`, `resources`, `relationships`,
`connections`, `topologies`, `imports`, `exports`, and `startup` blocks can stay
readable. A module must not split one section between the old and new location.

## One Spark host and two lowering passes

The combined Spark host loads these base extensions:

```elixir
[Jido.Agent.DSL.Extension, Jido.Topology.DSL.Extension]
```

One `:spark_dsl_config` attribute stores the complete declaration. The existing
Agent compiler reads `[:agent]` and `[:routes]`. The existing Topology compiler
reads paths below `[:topology]`. Thus Core reuses two semantic compilers without
using two Spark DSL hosts.

The `extensions:` option can contain Agent extensions, Topology extensions, or
an extension that implements both contracts. Core gives each extension only to
the matching lowering pass:

- `lower_agent/2` receives foreign entities below `agent`.
- `lower_topology/2` receives foreign Topology entities.

An extension that implements neither callback is invalid. Duplicate matching
extensions retain the existing Agent or Topology duplicate error. For example,
`Jido.AI.DSL` patches `[:agent]` and implements `lower_agent/2`; it composes
without any Topology-specific adapter.

## Constructor API

Agent and Topology modules currently both generate `new/1`. The two results are
not substitutable: one is `%Jido.Agent{}` and one is `%Jido.Topology.Instance{}`.
Argument inspection cannot resolve the collision because `id:` is valid for
both values.

Do not overload `new/1`. Use these names:

| Function | Result |
| --- | --- |
| `SupportTeam.owner/0` | Neutral owner `%Jido.Agent{}` definition |
| `SupportTeam.new_agent/1` | Owner `%Jido.Agent{}` instance |
| `SupportTeam.topology/0` | Static `%Jido.Topology{}` definition |
| `SupportTeam.instantiate/1` | Pure `%Jido.Topology.Instance{}` and plan |
| `SupportTeam.new/1` | Beta compatibility alias for `instantiate/1` |

The prototype retains the current `new/1` Topology meaning and adds
`new_agent/1`. `Jido.AgentServer.Options` now gives a declarative module with
`__agent_config__/0` precedence over a generic constructor module's `new/1`.
Therefore `Jido.start_agent(jido, SupportTeam, id: "support")` constructs the
owner Agent, while direct `SupportTeam.new(id: "support")` still constructs a
Topology instance. Constructor-only modules keep their current `new/0` or
`new/1` contract.

## Canonical owner representation

The next data-model change should make the owner explicit:

```elixir
%Jido.Topology{
  owner: %Jido.Agent{id: nil, state: nil, module: MyApp.SupportTeam},
  agents: [...],
  groups: [...],
  resources: [...]
}
```

The owner is a neutral Agent definition. It is static authoring data. It has no
runtime identity or state. `Jido.Topology.Codec` must encode it through the
existing Agent Codec and trusted Registry. This requires a Topology document
version increase. Older documents need a documented default-owner migration.

Instantiation creates the owner Agent instance and a plan owner descriptor:

```elixir
%Jido.Topology.Instance{
  id: "support",
  owner: %Jido.Agent{id: "support", state: %{...}},
  plan: %Jido.Topology.Plan{
    owner: %{id: "support", module: MyApp.SupportTeam},
    agents: %{"group/workers/1" => ...}
  }
}
```

Keep the owner outside `plan.agents`. The owner is the reconciliation authority;
the `agents` map is its desired child set. This prevents Agent counts, group
lookups, and controller code from treating the control plane as one ordinary
member. The owner Agent ID is the topology instance ID. Child IDs keep the
current `instance/agent/...` and `instance/group/...` forms.

An included topology contributes its `topology` graph only. It does not add a
second owner to the root instance. If an included component needs an active
coordinator, that coordinator must be an Agent entity in its `topology` block.
This keeps one runtime authority after composition and prevents nested owner
runtimes from starting the same composed members twice.

## Durable desired state

Static definitions must not enter mutable state. The owner Agent must hold only
the portable desired input and its revision coordinates. A built-in
`Jido.Topology.Plugin` should own a reserved state field such as:

```elixir
%{
  topology: %{
    input: %{worker_count: 3},
    definition_revision: 1
  }
}
```

The Topology definition, schemas, routes, plan, PIDs, and controller status stay
outside Agent state. The Plugin options identify the static topology module and
its input schema. The runtime can rebuild a plan from the current module and the
committed input.

Topology-changing Actions return typed Topology Plugin Directives. The Plugin
reduces those Directives into its owned desired state before commit. Its runtime
receives the same Directives after persistence succeeds and reconciles from the
committed Plugin state and `state_version`.

```text
Signal
  -> Action returns Topology Directive
  -> Topology Plugin updates desired input
  -> complete owner Agent checkpoint persists
  -> owner state commits
  -> Topology Plugin runtime reconciles children
```

This uses the current Agent Server order. `commit_checkpointed_turn/5` changes
live state only after `persist_commit/3` succeeds, and Plugin Directive dispatch
runs after that commit. A reconciliation failure must not undo the desired-state
commit. The runtime records the last reconciled state version and retries from
committed state, as the Scheduler and Sensor Manager runtimes already do.

## Startup API

Recommended public forms are:

```elixir
Jido.start_topology(MyApp.SupportTeam,
  id: "support",
  input: %{worker_count: 3}
)

Jido.start_topology(MyApp.Jido, MyApp.SupportTeam,
  id: "support",
  input: %{worker_count: 3}
)

MyApp.Jido.start_topology(MyApp.SupportTeam,
  id: "support",
  input: %{worker_count: 3}
)
```

Return `{:ok, owner_pid}`. The owner PID is the public live handle. Controller
PIDs are runtime observation, not topology identity.

`Jido.start_agent/3` with a Topology module starts only the owner Agent. It uses
Agent instance options and does not accept Topology `input:`. A new owner at
state version zero does not activate children. A restored owner can restart its
Topology Plugin runtime from committed desired state.

`Jido.start_topology/2` performs this sequence:

1. Validate the static Topology and input. Build the pure instance and plan.
2. Construct and start the owner through the normal `Jido.start_agent/3` path.
3. Send one internal bootstrap Signal that commits the initial desired input.
4. After that commit, dispatch a Topology Plugin Directive.
5. Wait for the Plugin runtime to reconcile the committed state.
6. Return the owner PID only after the requested readiness policy succeeds.

The bootstrap Turn is required. Current Agent startup does not persist a new
Agent at state version zero. Starting the controller during Plugin bootstrap
would activate children before their desired target is durable. A direct
pre-start persistence write would leave a stored Agent when process startup
fails. The normal Turn commit avoids both new failure windows.

On restart, Agent persistence restores the committed owner first. The Plugin
runtime reads its state and state version, rebuilds the instance plan, and then
reconciles. Child Agent persistence remains per child through the current
activation path.

## Controller changes

Keep one controller implementation, but change its authority boundary:

- The Topology Plugin runtime owns the controller process.
- The controller accepts a validated desired instance plus owner PID and state
  version.
- Reconcile can replace the target. It compares the new plan with observed
  members, keeps unchanged members, starts additions, and stops removals in
  reverse dependency order.
- A stale state version is ignored. One later version supersedes an active pass
  and produces one follow-up pass.
- Top-level child Agents are logically adopted by the owner after they start.
- Status identifies both desired and last reconciled owner state versions.

The current `Controller.reconcile/2` only repairs its original target. It cannot
serve as the post-commit update operation without this change.

## Smallest coherent core changes

The work has two safe units.

### Static authoring unit

- Make `Jido.Topology.DSL` the one combined Spark host.
- Let `Jido.Topology` reuse the Agent macro and compiler without Agent
  constructors.
- Nest the existing Topology sections below `topology` and retain temporary
  top-level compatibility paths.
- Partition additional extensions by `lower_agent/2` and `lower_topology/2`.
- Add `owner/0`, `new_agent/1`, and the declarative constructor precedence in
  Agent Server options.
- Add focused compile and live-owner tests.

This unit is the implemented prototype.

### Owner runtime unit

- Add the explicit owner fields to Topology, Instance, Plan, Builder, and Codec.
- Add `instantiate/1` and retain `new/1` as a beta alias.
- Add the Topology Plugin, desired-state Directive, runtime, and state-versioned
  controller update.
- Add `Jido.start_topology` and the `use Jido` facade wrapper.
- Move current direct-controller examples to the owner API after behavior is
  equivalent.

Do not land only the `start_topology` wrapper from this unit. It would keep the
current fixed controller target as a second authority.

## Compatibility risks

- `schema/0`, `routes/0`, `plugins/0`, and Agent route helpers now exist on a
  Topology module. Code that defined functions with those names can conflict.
- An extension list can now contain two contract families. Error text changes
  for an extension that implements neither family.
- Moving sections below `topology` changes Spark patch paths. During migration,
  Topology extensions can support both `[:agents]` and
  `[:topology, :agents]`; new extensions should use the nested path.
- A module cannot declare the same section in old and new locations.
- Encoding the owner requires a Topology Codec version increase and new trusted
  Registry entries for its Agent routes, Plugins, schemas, and metadata.
- The owner module becomes part of the static definition. Renaming it changes
  persistence restore and needs a migration decision.
- The reserved Plugin state key can conflict with an owner domain field or
  another Plugin. Validation must reject that conflict at compile time.
- Included owner blocks do not compose. Only the root owner runs. This rule must
  be prominent because it can surprise a user who expects owner routes from an
  included Topology.
- `Jido.start_agent` and `Jido.start_topology` use the same owner ID. Starting
  both for one ID must return the normal live-identity conflict and must not take
  over the existing process.
- Live target replacement needs a real plan diff. Restarting the complete
  controller is not equivalent because it replaces unchanged PIDs and can stop
  available work.

## Focused verification

The prototype tests prove:

- one module compiles one Agent block, normal routes, and nested Topology
  sections;
- Agent and Topology extensions lower through the same Spark host;
- a Topology-only extension does not enter the Agent lowerer;
- an Agent-only extension does not enter the Topology lowerer;
- `new/1` still returns a Topology instance and `new_agent/1` returns an Agent;
- `Jido.start_agent/3` starts the declarative owner instead of calling the
  Topology constructor;
- a missing `agent` block creates a valid neutral owner; and
- current top-level Topology blocks and extension tests remain valid.

The owner runtime unit needs additional tests:

- the bootstrap desired state is durably committed before the first child
  starts;
- a failed persistence write starts no reconciliation;
- a successful owner Turn replies with committed state before or independently
  of a later reconciliation error;
- restart restores owner desired state before it rebuilds the plan;
- growth, shrink, and definition changes retain unchanged child PIDs and state;
- stale reconciliation versions cannot replace a newer desired plan;
- composition runs one root owner and does not start included owners;
- `start_agent` starts only a new owner, while `start_topology` commits and
  activates the complete topology;
- owner shutdown stops the controller, Buses, and owned Agents; and
- identity conflicts never stop an unrelated owner or child Agent.
