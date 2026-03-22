# Multi-Tenancy

**After:** You can choose between hard isolation with separate Jido instances or logical partitioning inside one instance.

Jido supports multi-tenancy in two modes:

| Mode | Isolation Level | Best For |
|------|------------------|----------|
| **Isolated instances** | Hard isolation | Per-tenant config, smaller blast radius, clearer operations |
| **Shared-instance partitions** | Logical isolation | High-cardinality tenants, dynamic workspaces, lower runtime overhead |

Use separate Jido instances when you want the tenant boundary to align with supervisors, registries, runtime stores, and config. Use partitions when you want multiple logical tenants inside one Jido instance.

## What Jido Isolates

For shared-instance partitions, Jido scopes:

- Agent lookup and registry identity
- Parent/child relationship bindings
- Hibernate/thaw checkpoint identity
- `InstanceManager` keyed persistence
- Raw telemetry metadata (`jido_partition`)
- Runtime metadata in agent state (`agent.state.__partition__`)

Partitions do **not** create:

- Separate supervisor trees
- Separate task supervisors
- Separate runtime stores
- Separate debug controls
- Separate worker pools or quotas
- Automatic partitioning of external PubSub topics, buses, or HTTP targets

## Isolated Instances

This remains the recommended hard-isolation model.

```elixir
defmodule MyApp.TenantA.Jido do
  use Jido, otp_app: :my_app
end

defmodule MyApp.TenantB.Jido do
  use Jido, otp_app: :my_app
end
```

Each instance gets its own:

- Registry
- Agent supervisor
- Task supervisor
- Runtime store
- Storage configuration
- Debug/telemetry configuration

Choose this when tenants need strong operational separation.

## Shared-Instance Partitions

Use `partition:` when starting or looking up agents inside one Jido instance:

```elixir
{:ok, alpha_pid} = MyApp.Jido.start_agent(MyAgent, id: "session-1", partition: :alpha)
{:ok, beta_pid} = MyApp.Jido.start_agent(MyAgent, id: "session-1", partition: :beta)

MyApp.Jido.whereis("session-1", partition: :alpha)
MyApp.Jido.whereis("session-1", partition: :beta)

MyApp.Jido.list_agents(partition: :alpha)
MyApp.Jido.agent_count(partition: :beta)
```

Unpartitioned and partitioned identities are distinct. The same agent ID can exist:

- Unpartitioned
- In partition `:alpha`
- In partition `:beta`

Those do not collide.

## Lookup Rules

Partition lookup is explicit:

- `MyApp.Jido.whereis("id")` only checks the unpartitioned registry entry
- `MyApp.Jido.whereis("id", partition: :alpha)` only checks partition `:alpha`
- There is no implicit search across all partitions

The same rule applies to:

- `stop_agent`
- `list_agents`
- `agent_count`
- `hibernate`
- `thaw`
- `Jido.AgentServer.whereis/3`
- `Jido.AgentServer.via_tuple/3`

If you already have a pid or via tuple, you can still use that directly. That is the explicit cross-partition escape hatch.

## Hierarchy Rules

Parent/child behavior is partition-aware:

- Spawned children inherit the parent partition by default
- `Directive.spawn_agent/3` can override the child partition explicitly
- Adoption by child ID resolves only within the caller's partition
- Cross-partition adoption requires an explicit pid or via tuple

The current partition is mirrored into runtime state:

```elixir
agent.state.__partition__
```

Parent refs also retain the parent's partition:

```elixir
agent.state.__parent__.partition
```

## Persistence

Partitioned agents use partitioned checkpoint keys. Unpartitioned keys stay unchanged.

```elixir
:ok = MyApp.Jido.hibernate(agent, partition: :alpha)
{:ok, thawed} = MyApp.Jido.thaw(MyAgent, "session-1", partition: :alpha)
```

`InstanceManager` uses the same pattern:

```elixir
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123", partition: :alpha)
```

Manager persistence keys are partition-aware, so the same manager key can be reused safely in different partitions.

## Worker Pools

Worker pools remain instance-scoped in v1. They are **not** partition-aware.

Do not use pooled agents for tenant-specific mutable state unless you add your own reset or isolation layer around each checkout.

## Recommended Choice

Choose **isolated instances** when:

- A tenant boundary must be a clear operational boundary
- You need different config per tenant
- You want a smaller failure blast radius
- You want cleaner per-tenant observability and administration

Choose **partitions** when:

- You need many lightweight tenants in one runtime
- Tenants are dynamic or high-cardinality
- You want lower supervision overhead
- Logical separation is enough
