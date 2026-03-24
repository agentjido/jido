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
- `links` is optional topology metadata.
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
```

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
{:ok, pod_pid} = Jido.Agent.InstanceManager.get(:order_review_pods, "order-123")
{:ok, _started} = Jido.Pod.reconcile(pod_pid)
{:ok, reviewer_pid} = Jido.Pod.ensure_node(pod_pid, :reviewer)
```

`reconcile/2` eagerly acquires nodes marked `activation: :eager`.
`ensure_node/3` lazily acquires and adopts a named node on demand.

## Persistence

Pod durability uses the same `Persist` and `Storage` adapters as any other
agent because the topology snapshot lives in normal agent state.

This means storage adapters such as `jido_ecto` do not need a new storage
contract to support pods. If an adapter needs additive schema changes for
larger checkpoint payloads, those changes stay in the adapter package.

## Scope

This first slice keeps the model deliberately small:

- predefined topology only
- single-node runtime assumptions
- no pod-local signal bus
- no separate pod instance manager
- no automatic topology mutation protocol

The extension seam for later work is the `:__pod__` plugin state and the
canonical `%Jido.Pod.Topology{}` shape.
