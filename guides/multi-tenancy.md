# Multi-Tenancy

<!-- covers: jido.multi_tenancy.partition_namespace jido.multi_tenancy.pod_first_tenancy jido.multi_tenancy.partition_propagation -->

Jido now supports two distinct multi-tenancy models:

- separate Jido instances for hard isolation
- one shared Jido instance with `partition` as the logical tenant boundary

The second model is the one this guide focuses on.

If you are still deciding whether you need `partition` at all, or how it relates
to `InstanceManager` and `Pod`, start with
[Choosing a Runtime Pattern](runtime-patterns.md).

In shared-instance deployments, the recommended unit is:

- `partition` for tenant or workspace isolation
- a root `Jido.Pod` inside that partition for the durable runtime shape

That gives you a simple mental model:

- a tenant owns one or more root pods
- each pod owns a durable topology
- pod-managed children inherit the pod partition by default
- the same pod key can exist in multiple partitions without collisions

## Choose The Right Isolation Level

Use separate Jido instances when you need:

- different supervision trees
- different storage backends or runtime config
- strong operational isolation between tenants

Use one shared Jido instance with partitions when you want:

- one runtime to host many tenants or workspaces
- shared supervision and shared managers
- isolated registry identity, persistence, lineage, and telemetry per tenant

## Pod-First Model

The shared-instance model is intentionally Pod-first.

Instead of thinking in terms of “partitioned standalone agents,” think in terms
of “partitioned durable teams.”

```elixir
defmodule MyApp.WorkspacePod do
  use Jido.Pod,
    name: "workspace",
    topology: %{
      coordinator: %{
        agent: MyApp.WorkerAgent,
        manager: :workspace_workers,
        activation: :eager
      },
      reviewer: %{
        agent: MyApp.WorkerAgent,
        manager: :workspace_workers,
        activation: :lazy
      }
    }
end
```

Then acquire that pod inside a tenant partition:

```elixir
{:ok, workspace_pid} =
  Jido.Pod.get(:workspace_pods, "workspace-123", partition: :tenant_alpha)
```

That same key can exist in another partition:

```elixir
{:ok, other_workspace_pid} =
  Jido.Pod.get(:workspace_pods, "workspace-123", partition: :tenant_beta)
```

Those are two different pod runtimes with two different child trees.

## Setup

Typical shared-instance supervision looks like this:

```elixir
children = [
  MyApp.Jido,
  Jido.Agent.InstanceManager.child_spec(
    name: :workspace_workers,
    agent: MyApp.WorkerAgent,
    jido: MyApp.Jido
  ),
  Jido.Agent.InstanceManager.child_spec(
    name: :workspace_pods,
    agent: MyApp.WorkspacePod,
    jido: MyApp.Jido
  )
]
```

At runtime:

```elixir
{:ok, pod_pid} =
  Jido.Pod.get(:workspace_pods, "workspace-123", partition: :tenant_alpha)

{:ok, reviewer_pid} = Jido.Pod.ensure_node(pod_pid, :reviewer)
```

The worker manager is shared, but the runtime identity is not:

- `workspace-123` in `:tenant_alpha` is separate from `workspace-123` in `:tenant_beta`
- child lookups stay inside their partition
- hibernate/thaw stays inside its partition

## Runtime Rules

These are the important invariants:

- a pod tree is single-partition by default
- pod-managed children inherit the pod partition
- nested pod nodes inherit that same partition
- runtime parent bindings are stored per partition
- registry identity is per partition
- persistence identity is per partition
- telemetry includes `jido_partition`

That means these operations stay isolated automatically:

- `Jido.whereis/3`
- `Jido.Agent.InstanceManager.get/3`
- `Jido.Agent.InstanceManager.lookup/3`
- `Jido.Pod.get/3`
- `Jido.Pod.reconcile/2`
- `Jido.Pod.ensure_node/3`
- hibernate/thaw for agents and pods

## Hierarchies And Nested Pods

Partition inheritance is recursive through normal Pod runtime behavior.

If a root pod in `:tenant_alpha` starts:

- an eager worker
- a lazy worker
- a nested pod node

then all of those runtimes stay in `:tenant_alpha` unless you explicitly do
something unusual with raw pids.

That makes nested pods a good fit for workspace or team decomposition:

- root pod for the tenant workspace
- nested pods for domains like planning, editorial, or review

## Persistence And Thaw

Partition is part of the durable identity.

So if you stop a pod in one partition:

```elixir
:ok = Jido.Agent.InstanceManager.stop(:workspace_pods, "workspace-123", partition: :tenant_alpha)
```

that does not affect the same pod key in another partition.

On thaw:

- only the requested partition is restored
- surviving children reattach only inside that partition
- sibling tenant runtimes remain untouched

This is especially important for Pods because the durable topology snapshot and
the runtime ownership tree need to stay aligned at the tenant boundary.

## Cross-Partition Behavior

Normal pod behavior is partition-local.

That means:

- adoption by child id resolves within the caller’s partition
- child lookup by id resolves within the requested partition
- pod trees should not span partitions as a normal design pattern

There is still an escape hatch if you operate on raw pids directly, but that is
an explicit exception, not the default architecture.

If you need strong guarantees, keep pod trees single-partition.

## Observability

Partition now shows up in runtime metadata:

- debug events include `jido_partition`
- agent runtime telemetry includes `jido_partition`
- pod telemetry includes `jido_partition`

That makes it practical to:

- filter logs by tenant
- segment traces or metrics by tenant
- verify that reconcile/thaw behavior stayed in the expected partition

## Current Scope

This guide describes logical multi-tenancy inside one Jido instance.

Current scope:

- single-instance shared runtime
- single-node pod runtime model
- partition-safe Pods, children, nested pods, persistence, and telemetry

Not in scope here:

- distributed pod graphs across a cluster
- cross-partition pod trees as a first-class design
- tenant placement policies across multiple nodes

If you need hard operational isolation or different infrastructure per tenant,
prefer separate Jido instances.

## Example

The end-to-end runtime example for this model lives in:

- `test/examples/runtime/partitioned_pod_runtime_test.exs`

It demonstrates:

- same pod key in multiple partitions
- eager and lazy node isolation
- partition-preserving runtime lineage

## See Also

- [Pods](pods.md)
- [Configuration](configuration.md)
- [Persistence & Storage](storage.md)
