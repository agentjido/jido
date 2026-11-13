# Instances and Tenants

This guide explains what a Jido instance owns, how to configure one, and how to choose between instances and partitions when your system serves several tenants.

Jido gives you two separation tools, and neither one is a security boundary. See [Security Model](security.md) for what they do not protect.

## What an instance owns

An instance is one supervisor that you add to your application. Each instance has its own:

- Agent supervisor, which holds every activation.
- Registry, which maps Agent IDs to processes. Agent IDs are unique inside one instance and partition.
- Runner, which executes Turn work.
- Task supervisor, limited by `:max_tasks`.
- Default persistence adapter and AgentServer options.

Everything else is shared by the node: the `:jido` OTP application, its global Runner and Task supervisor, the telemetry handlers, the application environment, and the BEAM's memory and schedulers.

## Define an instance

`use Jido` creates a module that holds the instance's identity and reads its configuration. Add the module to your supervision tree.

```elixir
defmodule TenantGuide.Jido do
  use Jido, otp_app: :tenant_guide, namespace: "tenant-guide/primary"
end

Application.put_env(:tenant_guide, TenantGuide.Jido, max_tasks: 200)

{:ok, _pid} = TenantGuide.Jido.start_link(agent_server: [turn_timeout: 30_000])

[agent_server: [turn_timeout: 30_000], max_tasks: 200] =
  Enum.sort(TenantGuide.Jido.config(agent_server: [turn_timeout: 30_000]))
```

Options come from three places. Later sources win:

1. The `use Jido` options, which can only be `:otp_app`, `:namespace`, and `:persistence`.
2. `config :my_app, MyApp.Jido, ...` in the application environment.
3. Options passed to the child spec or `start_link/1`.

`Keyword.merge/2` combines them, so a nested list such as `:agent_server` replaces the earlier list as a whole.

For a script or Livebook, `Jido.start/1` starts one default instance. Later calls return the running PID and do not apply new options. Use a named module in an application.

### Instance options

| Option | Default | Meaning |
| --- | --- | --- |
| `:name` | Required for `Jido.start_link/1`. The module name under `use Jido`. | The instance name, a non-nil atom. |
| `:namespace` | `nil` | Stable identity for `Jido.Agent.Address` functions and durable records. |
| `:persistence` | `nil` | The default adapter, as a `Jido.Persistence.Store` module or `{module, options}`. |
| `:agent_server` | `[]` | Default options for each AgentServer in this instance. |
| `:max_tasks` | `1_000` | The child limit of the instance Task supervisor. A non-negative integer or `:infinity`. |
| `:debug` | Off | `true` or `:verbose` sets the instance log level. See Telemetry and Tracing. |
| `:otp_app` | None | The application that holds the configuration. |

`Jido.start_link/1` rejects an unknown or repeated key with a `Jido.Error.ValidationError`. The child spec raises the same error, so a bad option stops your application at boot.

```elixir
{:error, %Jido.Error.ValidationError{details: %{keys: [:max_task]}}} =
  Jido.start_link(name: TenantGuide.Misspelled, max_task: 10)
```

## Set AgentServer defaults

`:agent_server` sets defaults for each Agent in the instance. An option passed to `Jido.start_agent/3` overrides them. The full order is:

1. The option passed to `Jido.start_agent/3`.
2. The instance `:agent_server` option.
3. For `:turn_timeout` only, `config :jido, Jido.AgentServer, turn_timeout: milliseconds`.
4. The built-in default.

```elixir
defmodule TenantGuide.Ticket do
  use Jido.Agent, name: "tenant_guide_ticket"

  state do
    schema Jido.Joi.object(%{status: Jido.Joi.string() |> Jido.Joi.default("open")})
  end
end

{:ok, _pid} =
  Jido.start_link(name: TenantGuide.Support, agent_server: [max_postponed_signals: 50])

{:ok, standard} = Jido.start_agent(TenantGuide.Support, TenantGuide.Ticket, id: "ticket-1")

{:ok, strict} =
  Jido.start_agent(TenantGuide.Support, TenantGuide.Ticket, id: "ticket-2", max_postponed_signals: 5)

50 = Jido.AgentServer.status(standard).admission.limit
5 = Jido.AgentServer.status(strict).admission.limit
```

[Production Setup](production-configuration.md) covers which values to set.

## Understand the three scopes

| Scope | Form | Separates | Created at runtime? |
| --- | --- | --- | --- |
| Instance | Atom | Processes, Task limit, adapter, and defaults | No. Use a fixed set. |
| Namespace | Nonempty string | Durable identity. Part of every `Jido.Agent.Address`. | No. One per instance. |
| Partition | Nonempty string, or none | Agent IDs and durable records inside one instance | Yes |

A durable record's key is the exact `{namespace, partition, id}` tuple. Changing a namespace or partition points to different records. It does not move the old ones.

### Namespace rules

One namespace can bind to one live instance per node. A second instance gets an error.

```elixir
{:ok, _pid} = Jido.start_link(name: TenantGuide.Billing, namespace: "tenant-guide/billing")

{:error, %Jido.Error.ValidationError{details: %{code: :jido_namespace_already_bound}}} =
  Jido.start_link(name: TenantGuide.BillingCopy, namespace: "tenant-guide/billing")
```

This check is local to the node. Two nodes can bind one namespace to one store, and they then share its records. See [Deployment and Sizing](deployment-and-performance.md#run-more-than-one-node).

An instance with no namespace can run Agents, but `Jido.agent_address/3` returns an error with code `:jido_namespace_required`, and a persistent Agent cannot start.

### Partitions

Pass `:partition` when you start an Agent. Each lookup must name the same partition.

```elixir
{:ok, acme} =
  Jido.start_agent(TenantGuide.Billing, TenantGuide.Ticket, id: "ticket-1", partition: "acme")

{:ok, globex} =
  Jido.start_agent(TenantGuide.Billing, TenantGuide.Ticket, id: "ticket-1", partition: "globex")

^acme = Jido.whereis_agent(TenantGuide.Billing, "ticket-1", partition: "acme")
^globex = Jido.whereis_agent(TenantGuide.Billing, "ticket-1", partition: "globex")

nil = Jido.whereis_agent(TenantGuide.Billing, "ticket-1")
[] = Jido.list_agents(TenantGuide.Billing)
[{"ticket-1", ^acme}] = Jido.list_agents(TenantGuide.Billing, partition: "acme")

{:ok, address} = Jido.agent_address(TenantGuide.Billing, "ticket-1", partition: "acme")
{:ok, ^acme} = Jido.resolve_agent(TenantGuide.Billing, address)
```

`Jido.list_agents/2` and `Jido.resident_agent_count/2` read one partition at a time. Without `:partition`, they count only Agents with no partition. Jido has no function that lists partitions, so your application keeps that list.

## Choose a tenant model

Use one partition per tenant unless a tenant needs its own adapter or defaults.

| Need | Use |
| --- | --- |
| Tenants that you create at runtime | Partitions |
| The same Agent ID for different tenants | Partitions or instances |
| A separate database or bucket for each tenant class | Instances, one per class |
| Different timeouts or queue limits for a class | Instances, or per-Agent options |
| Separate memory, CPU, or crash domains | Separate BEAM nodes |

Do not create an instance for each tenant at runtime. Each instance name becomes several atoms, and atoms are never collected. Instance names should come from your code, never from request data.

### What a partition does not do

Agents in different partitions of one instance share a Runner, a Task supervisor, and a persistence adapter. Jido has:

- No rate limit, quota, or fair scheduling between partitions or instances. A queue limit applies to one Agent.
- No access check. A caller that can reach an instance can use any partition. Check the tenant in your application before you build a `Jido.Agent.Address` or look up an Agent.
- No tenant label on Turn telemetry. Turn events carry `agent_id` and `agent_module`, but no instance, namespace, or partition. Persistence events carry `agent_namespace` and `agent_partition`. If you report by tenant, encode the tenant in the Agent ID or keep your own mapping.

## Next steps

- [Production Setup](production-configuration.md)
- [Start and Address Agents](../agent-servers/start-and-address-live-agents.livemd)
- Durability Model
