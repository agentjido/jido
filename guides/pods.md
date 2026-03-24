# Pods

`Jido.Pod` is the simplest durable topology layer in core Jido: a pod is just an
agent with a canonical topology snapshot and a reserved singleton plugin mounted
under `:__pod__`.

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

- `:depends_on` orders eager reconciliation when both nodes are eager
  `kind: :agent` members
- `:owns` is descriptive topology metadata only

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

If you need lower-level control, you can still call
`Jido.Agent.InstanceManager.get/3` directly and then invoke `Jido.Pod.reconcile/2`
yourself.

## Hierarchical Topologies Today

You can describe hierarchy-like intent in the topology data:

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

That is a **topology description**, not nested durable runtime parentage.

Current runtime behavior is intentionally flat:

- the pod agent is the single durable manager
- all runtime-managed nodes are reconciled as manager-owned members
- `:depends_on` affects eager `kind: :agent` reconciliation order only
- `:owns` is metadata only
- `kind: :pod` is accepted by the topology shape for future evolution, but
  runtime helpers reject it with a clear unsupported-kind error today

So the honest answer is: **no, durable hierarchical pod runtime is not here
yet**. You can model hierarchy in the topology data, but the runtime semantics
remain manager-led and flat in this first slice.

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
2. runtime relationships are re-established explicitly with `reconcile/2` and
   `ensure_node/3`

Example:

```elixir
{:ok, pod_pid} = Jido.Pod.get(:order_review_pods, "order-123")

# Later: the pod manager hibernates and is restored
{:ok, restored_pid} = Jido.Agent.InstanceManager.get(:order_review_pods, "order-123")
{:ok, topology} = Jido.Pod.fetch_topology(restored_pid)
{:ok, snapshots} = Jido.Pod.nodes(restored_pid)

# Low-level: explicitly re-adopt eager nodes after thaw
{:ok, _started} = Jido.Pod.reconcile(restored_pid)
```

After thaw:

- eager nodes can be re-adopted with `reconcile/2`
- surviving lazy nodes show up as `:running` until explicitly adopted
- `ensure_node/3` handles either case: start fresh or re-adopt existing

So there is no extra storage adapter architecture for pods. The extra durability
need is **runtime reconciliation after thaw**, not a new persistence contract.

## Scope

This first slice keeps the model deliberately small:

- predefined topology only
- flat manager-led runtime semantics
- single-node runtime assumptions
- no pod-local signal bus
- no separate pod instance manager
- no automatic topology mutation protocol

The extension seam for later work is the `:__pod__` plugin state and the
canonical `%Jido.Pod.Topology{}` shape.

## See Also

- [Runtime](runtime.md) for live hierarchy and adoption behavior
- [Persistence & Storage](storage.md) for checkpoint and thaw invariants
- [Multi-Agent Orchestration](orchestration.md) for ephemeral `SpawnAgent`
  coordination patterns
- [Plugins](plugins.md#default-plugins) for reserved plugin state keys and
  override semantics
