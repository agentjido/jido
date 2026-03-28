# Choosing A Runtime Pattern

Jido now has a few different runtime building blocks, and they are close enough
that it is easy to reach for the wrong one.

This guide is the short decision tree.

## The Simple Mental Model

- use `Jido.start_agent/2` or `Jido.AgentServer.start_link/1` for one live agent
- use `Directive.SpawnAgent` for a live tracked child of the current parent
- use `Jido.Agent.InstanceManager` for one named durable agent
- use `Jido.Pod` for one named durable team of agents
- use `partition` to namespace any of the above in a shared Jido instance

The important boundary is this:

- lifecycle is chosen by `AgentServer`, `SpawnAgent`, `InstanceManager`, or `Pod`
- tenancy is chosen by `partition`

`partition` is not a lifecycle mechanism by itself. It is a namespace boundary.

## Pick The Right Tool

| Need | Use | Why |
| --- | --- | --- |
| A single live process right now | `Jido.start_agent/2` or `Jido.AgentServer.start_link/1` | Smallest runtime surface |
| A child that should be tracked by the current parent during this live workflow | `Directive.SpawnAgent` | Logical hierarchy, child exit signals, parent-child routing |
| A single named agent that may hibernate and thaw later | `Jido.Agent.InstanceManager` | Durable keyed lifecycle for one agent |
| A named group of agents with a durable topology | `Jido.Pod` | Durable team/workspace/unit with explicit reconcile semantics |
| Many tenants or workspaces in one shared Jido instance | `partition` | Isolates registry identity, persistence, lineage, and telemetry |

## When To Use `SpawnAgent`

Use `SpawnAgent` when the child is part of the current live workflow:

- worker fan-out
- short-lived coordinators
- ephemeral sub-agents
- parent-owned runtime behavior

Good fit:

```elixir
Directive.spawn_agent(MyWorker, :researcher,
  opts: %{id: "research-1", on_parent_death: :stop}
)
```

Do not use `SpawnAgent` when what you really want is:

- storage-backed hibernate/thaw
- durable keyed reacquisition
- a named runtime that should survive independently of one parent turn

That is `InstanceManager` territory instead.

## When To Use `InstanceManager`

Use `Jido.Agent.InstanceManager` when the durable unit is one named agent:

```elixir
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")
```

That gives you:

- keyed lookup
- optional storage-backed thaw
- ordinary single-agent runtime semantics

If the durable unit is a team or workspace with multiple named members, that is
no longer “one durable agent.” That is where `Jido.Pod` starts to make sense.

## When To Use `Pod`

Use `Jido.Pod` when the durable unit is a structured team:

- a workspace
- a named pipeline
- an editorial or planning team
- a durable agent tree with eager and lazy members

```elixir
{:ok, pod_pid} = Jido.Pod.get(:workspace_pods, "workspace-123")
{:ok, reviewer_pid} = Jido.Pod.ensure_node(pod_pid, :reviewer)
```

Pods are the right abstraction when you care about:

- durable topology
- manager-led reconcile after thaw
- hierarchical runtime ownership
- nested pod nodes

Pods are not just “a nicer `SpawnAgent`.” They are the durable topology layer.

## Where `partition` Fits

`partition` is orthogonal to the runtime model.

You can use it with:

- direct agent starts
- `InstanceManager`
- Pods

In practice, the most useful shared-instance model is:

- `partition` isolates a tenant or workspace namespace
- a root `Jido.Pod` is the durable unit inside that namespace

```elixir
{:ok, alpha_pod} = Jido.Pod.get(:workspace_pods, "workspace-123", partition: :tenant_alpha)
{:ok, beta_pod} = Jido.Pod.get(:workspace_pods, "workspace-123", partition: :tenant_beta)
```

Same key, different tenant runtime.

## Orphans And Adoption Are Advanced

Orphans and adoption are not the default lifecycle story. They are the advanced
exception when a live child must outlast the logical parent that started it.

Reach for them when:

- in-flight work must survive coordinator death
- reattachment is explicit business logic

Do not use them as a substitute for durable keyed lifecycle. If you need
hibernate/thaw or named reacquisition, use `InstanceManager` or `Pod`.

## Recommended Defaults

If you are unsure, start here:

1. One live agent: `Jido.start_agent/2`
2. Live tracked child: `Directive.SpawnAgent`
3. One durable named agent: `InstanceManager`
4. One durable named team: `Pod`
5. Need shared-instance tenancy: add `partition`

That keeps the architecture legible and avoids reaching for the heaviest tool
too early.

## See Also

- [Runtime](runtime.md)
- [Persistence & Storage](storage.md)
- [Pods](pods.md)
- [Multi-Tenancy](multi-tenancy.md)
- [Orphans & Adoption](orphans.md)
