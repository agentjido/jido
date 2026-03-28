# Pods

<!-- covers: jido.pods.durable_topology jido.pods.reconcile_and_lazy_activation jido.pods.nested_pods jido.pods.live_mutation -->

`Jido.Pod` is the simplest durable topology layer in core Jido: a pod is just an
agent with a canonical topology snapshot and a reserved singleton plugin mounted
under `:__pod__`.

If you are still choosing between `SpawnAgent`, `InstanceManager`, and `Pod`,
start with [Choosing a Runtime Pattern](runtime-patterns.md).

## What A Pod Is

- A pod module is an ordinary `Jido.Agent` module.
- The pod module itself is the durable manager for the topology.
- `topology` is pure data, represented by `%Jido.Pod.Topology{}`.
- Member nodes are durable collaborators acquired through ordinary
  `Jido.Agent.InstanceManager` registries.

Pods do not add a separate runtime manager process or a special instance manager.
Use the existing `Jido.Agent.InstanceManager` for the pod agent itself.

## Defining A Pod

```elixir
defmodule MyApp.OrderReviewPod do
  use Jido.Pod,
    name: "order_review",
    topology: %{
      planner: %{agent: MyApp.PlannerAgent, manager: :planner_members, activation: :eager},
      reviewer: %{agent: MyApp.ReviewerAgent, manager: :reviewer_members, activation: :lazy}
    },
    schema: [
      phase: [type: :atom, default: :planning]
    ]
end
```

This wraps `use Jido.Agent` and injects a singleton pod plugin under `:__pod__`.

`topology:` may also be omitted to start with an empty named topology:

```elixir
defmodule MyApp.EmptyReviewPod do
  use Jido.Pod,
    name: "empty_review"
end
```

If you are just getting started, you can skip the next two reference sections
and jump to [Running A Pod](#running-a-pod).

## Happy Path

Most users only need this flow:

- define a pod with `use Jido.Pod`
- run the pod manager through a normal `Jido.Agent.InstanceManager`
- call `Jido.Pod.get/3` to load the durable team and reconcile eager members
- call `Jido.Pod.ensure_node/3` for lazy members
- call `Jido.Pod.mutate/3` only when the durable team needs to grow or shrink

If you only read one example, start with [Canonical Example](#canonical-example)
below. The fully runnable example lives in
`test/examples/runtime/mutable_pod_runtime_test.exs`.

## Canonical Example

This is the shortest end-to-end Pod story in core Jido:

```elixir
defmodule MyApp.ReviewWorkerAgent do
  use Jido.Agent,
    name: "review_worker",
    schema: [
      role: [type: :string, default: "worker"]
    ]
end

defmodule MyApp.ReviewPod do
  use Jido.Pod,
    name: "review_pod"
end

children = [
  Jido.Agent.InstanceManager.child_spec(
    name: :review_workers,
    agent: MyApp.ReviewWorkerAgent,
    storage: {Jido.Storage.ETS, table: :review_runtime}
  ),
  Jido.Agent.InstanceManager.child_spec(
    name: :review_pods,
    agent: MyApp.ReviewPod,
    storage: {Jido.Storage.ETS, table: :review_runtime}
  )
]

{:ok, pod_pid} = Jido.Pod.get(:review_pods, "review-123")

{:ok, report} =
  Jido.Pod.mutate(
    pod_pid,
    [
      Jido.Pod.Mutation.add_node("planner", %{
        agent: MyApp.ReviewWorkerAgent,
        manager: :review_workers,
        activation: :eager,
        initial_state: %{role: "planner"}
      }),
      Jido.Pod.Mutation.add_node(
        "reviewer",
        %{
          agent: MyApp.ReviewWorkerAgent,
          manager: :review_workers,
          activation: :lazy,
          initial_state: %{role: "reviewer"}
        },
        owner: "planner",
        depends_on: ["planner"]
      )
    ]
  )

{:ok, reviewer_pid} = Jido.Pod.ensure_node(pod_pid, "reviewer")
```

What this demonstrates:

- the pod itself is one durable keyed runtime
- topology is stored as ordinary pod state under `:__pod__`
- eager members start during `get/3` or mutation reconciliation
- lazy members stay defined but stopped until `ensure_node/3`
- later reacquisition restores the same durable topology before reconcile

## Pod Plugin

The default pod plugin is `Jido.Pod.Plugin`.

- It is always singleton.
- It uses the reserved state key `:__pod__`.
- It persists the resolved topology snapshot as ordinary agent state.
- It advertises the `:pod` capability.

You can replace it through the normal `default_plugins` override path:

```elixir
defmodule MyApp.CustomPod do
  use Jido.Pod,
    name: "custom_pod",
    topology: %{
      worker: %{agent: MyApp.WorkerAgent, manager: :workers}
    },
    default_plugins: %{__pod__: MyApp.CustomPodPlugin}
end
```

Replacement plugins must keep the same `:__pod__` state key, be singleton, and
advertise the `:pod` capability.

## Topology

`Jido.Pod.Topology` is the canonical topology data structure.

- `name` is the stable topology name.
- `nodes` is a map of logical node name to `%Jido.Pod.Topology.Node{}`.
- `links` is a list of `%Jido.Pod.Topology.Link{}`.
- `version` is a simple topology version integer.
  `Jido.Pod.put_topology/2` and `Jido.Pod.update_topology/2` advance it when
  the structural topology changes and preserve it for no-op rewrites.

Node names may be atoms or strings. Static predefined pods can keep atom names,
while runtime-defined or persisted dynamic nodes can use strings. Mixed
topologies are supported.

The topology API is pure:

```elixir
{:ok, topology} =
  Jido.Pod.Topology.from_nodes("review", %{
    planner: %{agent: MyApp.PlannerAgent, manager: :planner_members}
  })

{:ok, topology} =
  Jido.Pod.Topology.put_node(
    topology,
    :reviewer,
    %{agent: MyApp.ReviewerAgent, manager: :reviewer_members}
  )

{:ok, topology} =
  Jido.Pod.Topology.put_link(
    topology,
    {:depends_on, :reviewer, :planner}
  )
```

Tuple shorthand links are normalized into canonical `%Jido.Pod.Topology.Link{}`
structs for storage and inspection.

In v1, links support a small fixed vocabulary:

- `:depends_on` defines runtime prerequisites and eager reconciliation order
- `:owns` defines the logical runtime owner for supported `kind: :agent` nodes

## Running A Pod

Pods run through ordinary `Jido.Agent.InstanceManager` registries:

```elixir
children = [
  Jido.Agent.InstanceManager.child_spec(
    name: :order_review_pods,
    agent: MyApp.OrderReviewPod,
    storage: {Jido.Storage.ETS, table: :pods}
  )
]
```

```elixir
{:ok, pod_pid} = Jido.Pod.get(:order_review_pods, "order-123")
{:ok, reviewer_pid} = Jido.Pod.ensure_node(pod_pid, :reviewer)
```

`Jido.Pod.get/3` is the default happy path: it gets the pod manager through the
ordinary `InstanceManager` and immediately reconciles eager nodes.

`reconcile/2` eagerly acquires nodes marked `activation: :eager`.
`ensure_node/3` lazily acquires and adopts a named node on demand.

Ownership matters at runtime:

- root nodes with no `:owns` parent are adopted directly into the pod manager
- owned nodes are adopted under their logical owner node
- `:depends_on` and `:owns` are combined into reconcile waves so prerequisites
  are running before descendants are adopted
- `kind: :pod` nodes are acquired through their own `InstanceManager`, adopted
  into the ownership tree, and then reconciled recursively
- recursive pod ancestry is still rejected explicitly to avoid infinite runtime
  expansion

If you need lower-level control, you can still call
`Jido.Agent.InstanceManager.get/3` directly and then invoke `Jido.Pod.reconcile/2`
yourself.

## Core API

Most applications only need these entry points:

- `Jido.Pod.get/3` loads the durable pod and reconciles eager members
- `Jido.Pod.ensure_node/3` starts or re-adopts one named member
- `Jido.Pod.reconcile/2` repairs eager roots and ownership edges explicitly
- `Jido.Pod.fetch_topology/1` reads the current durable topology snapshot
- `Jido.Pod.mutate/3` changes the durable topology of a running pod

## Partitioned Pods

Pods now work cleanly with Jido's logical `partition` boundary.

For the full shared-instance tenancy model, see [Multi-Tenancy](multi-tenancy.md).

That gives you two tenancy models:

- separate Jido instances for hard isolation
- one shared Jido instance with `partition` as the tenant/workspace namespace

In the shared-instance model, the pod is the durable unit and the partition is
the namespace around it:

```elixir
{:ok, alpha_pod} = Jido.Pod.get(:order_review_pods, "order-123", partition: :alpha)
{:ok, beta_pod} = Jido.Pod.get(:order_review_pods, "order-123", partition: :beta)
```

Those are two different pod runtimes, even though they share the same pod key.

Partition behavior is intentionally simple:

- the pod manager runtime has one partition
- pod-managed children inherit that partition by default
- nested pod nodes inherit that same partition
- persistence, registry lookup, parent bindings, and pod telemetry all stay in
  that partition

So the normal mental model is:

- `partition` isolates tenants or workspaces
- `Jido.Pod` gives each tenant/workspace a durable structured runtime

Cross-partition interaction is still explicit and exceptional. A pod tree is
single-partition by default.

## Live Mutation

Pods now support live add/remove topology mutation on a running pod manager.

`Jido.Pod.mutate/3` is the external synchronous API:

```elixir
{:ok, report} =
  Jido.Pod.mutate(
    pod_pid,
    [
      Jido.Pod.Mutation.add_node(
        "reviewer",
        %{agent: MyApp.ReviewerAgent, manager: :reviewer_members, activation: :eager},
        owner: "planner",
        depends_on: ["planner"]
      )
    ]
  )
```

Pass a running pod pid or another `Jido.AgentServer` server reference that the
runtime can resolve directly. Raw string ids still need explicit registry lookup
before they can be used as the `server` argument.

This slice supports:

- batched `add_node` and `remove_node` operations
- `kind: :agent` and `kind: :pod` nodes
- ownership and dependency links embedded on add ops
- mixed atom/string node names in the same topology

This slice does **not** support:

- standalone link mutation
- reparenting a surviving node
- multi-node pod runtime semantics

Mutation semantics are persistence-first:

1. the new topology snapshot is written into `agent.state[:__pod__]`
2. runtime stop/start work runs against that new topology
3. the returned `%Jido.Pod.Mutation.Report{}` records `added`, `removed`,
   `started`, `stopped`, and `failures`

If runtime work partially fails, the topology stays updated and the mutation
returns `{:error, report}`. Recovery is explicit through later
`Jido.Pod.reconcile/2`, `Jido.Pod.ensure_node/3`, or another mutation.

For in-turn pod code, `Jido.Pod.mutation_effects/3` returns the state ops and
runtime directive for the same mutation path instead of executing the mutation
immediately.

Removals are subtree-aware: removing a node removes its owned descendants,
deletes links touching the removed nodes, and tears down live runtime state in
reverse ownership/dependency order.

## Hierarchical Runtime Ownership

Pods support hierarchical runtime ownership for both `kind: :agent` and
`kind: :pod` nodes:

```elixir
topology =
  Jido.Pod.Topology.new!(
    name: "editorial_pipeline",
    nodes: %{
      lead: %{agent: MyApp.LeadAgent, manager: :editorial_leads, activation: :eager},
      review: %{agent: MyApp.ReviewAgent, manager: :editorial_reviews},
      publish: %{agent: MyApp.PublishAgent, manager: :editorial_publish}
    },
    links: [
      {:owns, :lead, :review},
      {:owns, :lead, :publish},
      {:depends_on, :publish, :review}
    ]
  )
```

In that example:

- `lead` is a root node owned by the pod manager
- `review` is owned by `lead`
- `publish` is also owned by `lead`
- `publish` will not reconcile until `review` is running because of
  `{:depends_on, :publish, :review}`

Nested pods work the same way, except the node process is itself another pod
manager:

```elixir
topology =
  Jido.Pod.Topology.new!(
    name: "program",
    nodes: %{
      coordinator: %{agent: MyApp.CoordinatorAgent, manager: :coordinators, activation: :eager},
      editorial: %{module: MyApp.EditorialPod, manager: :editorial_pods, kind: :pod, activation: :eager}
    },
    links: [
      {:owns, :coordinator, :editorial}
    ]
  )
```

In that case:

- `editorial` is started through `:editorial_pods`
- the `editorial` pod manager is adopted under `coordinator`
- the nested pod then reconciles its own eager topology
- thaw repairs the broken ownership edge at the outer pod boundary, then the
  nested pod repairs its own eager edges when reconciled

So the honest answer is:

- **yes** for nested durable pod-of-pod runtime semantics on a single node
- **no** for recursive pod ancestry; a pod cannot expand back into itself in the
  current runtime

## Persistence, Storage, And Thaw

Pod durability uses the same `Persist` and `Storage` adapters as any other
agent because the topology snapshot lives in normal agent state.

This means storage adapters such as `jido_ecto` do not need a new storage
contract to support pods. If an adapter needs additive schema changes for
larger checkpoint payloads, those changes stay in the adapter package.

What is persisted:

- `agent.state[:__pod__].topology`
- `agent.state[:__pod__].topology_version`
- any pod-plugin metadata you keep under `:__pod__`

What is **not** persisted as durable truth:

- live child PIDs
- monitors
- `AgentServer` `state.children`
- a live process tree

That means pod thaw is a two-step story:

1. the pod agent thaws with its topology snapshot already restored
2. root relationships are re-established explicitly with `reconcile/2` and
   `ensure_node/3`

Example:

```elixir
{:ok, pod_pid} = Jido.Pod.get(:order_review_pods, "order-123")

# Later: the pod manager hibernates and is restored
{:ok, restored_pid} = Jido.Agent.InstanceManager.get(:order_review_pods, "order-123")
{:ok, topology} = Jido.Pod.fetch_topology(restored_pid)
{:ok, snapshots} = Jido.Pod.nodes(restored_pid)

# Low-level: explicitly reconcile eager roots after thaw
{:ok, report} = Jido.Pod.reconcile(restored_pid)
```

After thaw:

- surviving root nodes show up as `:running` until explicitly re-adopted
- owned descendants can remain `:adopted` if their logical owner survived
- surviving nested pod managers can remain `:running` or `:adopted` depending on
  whether their immediate owner survived
- `reconcile/2` repairs the root boundary and any missing ownership edges for
  eager nodes
- `ensure_node/3` handles either case: start fresh, re-adopt a root, or
  reattach an owned descendant under its owner
- nested pod nodes reconcile their own eager topology after they are reattached

So there is no extra storage adapter architecture for pods. The extra durability
need is **runtime reconciliation after thaw**, not a new persistence contract.

## Scope

This first slice keeps the model deliberately small:

- predefined topology only
- live add/remove mutation for running pods
- hierarchical ownership for `kind: :agent` and `kind: :pod` nodes
- pod manager as the durable root
- single-node runtime assumptions
- no pod-local signal bus
- no separate pod instance manager
- no recursive pod ancestry
- no standalone link mutation
- no reparenting of surviving nodes

The extension seam for later work is the `:__pod__` plugin state and the
canonical `%Jido.Pod.Topology{}` shape.

## See Also

- [Runtime](runtime.md) for live hierarchy and adoption behavior
- [Persistence & Storage](storage.md) for checkpoint and thaw invariants
- [Multi-Agent Orchestration](orchestration.md) for ephemeral `SpawnAgent`
  coordination patterns
- [Plugins](plugins.md#default-plugins) for reserved plugin state keys and
  override semantics
