# Instances and Tenants

A Jido instance is a supervisor that owns a registry, a task supervisor, a
workflow runner, and the Agent Servers started under it. You define one per
application with `use Jido`, configure it from your app config, and
partition its Agents per tenant. This guide shows each option, how defaults
combine, and where isolation stops.

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

```elixir
# config/config.exs
config :my_app, MyApp.Jido,
  max_tasks: 500,
  agent_server: [turn_timeout: 30_000]
```

```elixir
# lib/my_app/application.ex
children = [
  MyApp.Jido
]
```

```elixir
MyApp.Jido.config()
# => [max_tasks: 500, agent_server: [turn_timeout: 30000]]

{:ok, pid} = MyApp.Jido.start_agent(MyApp.Counter, id: "counter-1")
```

## Options

`use Jido` takes `otp_app:` (required), `namespace:`, and `persistence:`.
Start options and the `config :my_app, MyApp.Jido` keyword list accept:

| Option | Default | Use |
| --- | --- | --- |
| `:namespace` | `nil` | Stable identity for Refs and storage. Required for persistent Agents. |
| `:max_tasks` | `1_000` | Limit on the instance task supervisor. A non-negative integer or `:infinity`. |
| `:agent_server` | `[]` | Default options for every Agent Server in the instance. |
| `:persistence` | None | Storage adapter for persistent Agents. See [Storage Model](persistence-storage-model.md). |
| `:debug` | `false` | `true` or `:verbose` turns on instance debug logs. |
| `:name` | The module | Registered name of the supervisor. |
| `:otp_app` | From `use Jido` | Application that holds the config. |

Options passed to `start_link/1` override app config:

```elixir
{MyApp.Jido, max_tasks: 2_000}
```

An unknown key stops startup with `"Jido instance options contain unknown
keys"` and `code: :jido_instance_invalid_config`.

## Server Defaults

An Agent Server option comes from the first of:

1. the options passed to `start_agent/2`;
2. the instance `agent_server:` list;
3. `config :jido, Jido.AgentServer, turn_timeout: ...`; and
4. the built-in default.

```elixir
# instance agent_server: [turn_timeout: 30_000]
{:ok, a} = MyApp.Jido.start_agent(MyApp.Counter, id: "a")
{:ok, b} = MyApp.Jido.start_agent(MyApp.Counter, id: "b", turn_timeout: 10_000)

{Jido.AgentServer.status(a).turn_timeout, Jido.AgentServer.status(b).turn_timeout}
# => {30000, 10000}
```

`config :jido, Jido.AgentServer` accepts only `:turn_timeout`. It sets the
node-wide fallback, which is 60,000 ms when unset. An invalid key in the
instance `agent_server:` list fails startup with
`"invalid instance AgentServer defaults"`.

## Namespaces

The namespace is the instance's stable identity. Jido puts it in every Agent
Ref and every persistence key. It is `nil` by default. Set it before you use
persistence or Refs:

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app, namespace: "my-app/agents"
end
```

One namespace binds to one live instance per node. A second instance with
the same namespace fails to start:

```text
%Jido.Error.ValidationError{
  message: "Jido instance namespace is already bound",
  details: %{code: :jido_namespace_already_bound, ...}
}
```

The binding is released when the instance stops. Keep a namespace stable
across deploys. A new namespace can't read Agents saved under the old one.

## Multiple Instances

Each instance has its own registry, task supervisor, runner, and Agent
supervisor. The same Agent ID can run in two instances:

```elixir
defmodule MyApp.Billing do
  use Jido, otp_app: :my_app
end

defmodule MyApp.Support do
  use Jido, otp_app: :my_app
end

{:ok, _} = MyApp.Billing.start_agent(MyApp.Counter, id: "acme")
{:ok, _} = MyApp.Support.start_agent(MyApp.Counter, id: "acme")
```

Use separate instances when the parts of your system need different storage,
different limits, or separate shutdown. Use partitions when they need only
separate Agent identity.

## Partitions

A partition is a named Agent ID space inside one instance. Pass it when you
start or look up an Agent:

```elixir
{:ok, _} = MyApp.Jido.start_agent(MyApp.Counter, id: "acme-1")
{:ok, _} = MyApp.Jido.start_agent(MyApp.Counter, id: "acme-1", partition: "tenant-b")

MyApp.Jido.whereis_agent("acme-1", partition: "tenant-b")
# => #PID<0.312.0>

MyApp.Jido.list_agents(partition: "tenant-b")
# => [{"acme-1", #PID<0.312.0>}]

MyApp.Jido.agent_count(partition: "tenant-b")
# => 1
```

Rules:

- A partition is a nonempty string. `""` fails with
  `"invalid Jido instance, partition, or Runner ownership"`.
- Without `partition:`, calls use the default partition. `list_agents/1`
  with no option lists only the default partition.
- An ID is unique inside one partition. A second start with the same ID and
  partition returns an error.
- An Agent's identity is the namespace, partition, and ID together.
  `Jido.AgentServer.status(pid).partition` returns the partition.

Map one tenant to one partition. Derive the partition from the authenticated
tenant on the server side. Never take it from client input.

## Environment Values

`Jido.Config.env/1` marks a value to read from the environment when you
resolve it. Use it in options that hold secrets:

```elixir
opts = [api_key: Jido.Config.env("BILLING_API_KEY"), retries: 3]

Jido.Config.resolve(opts)
# => {:ok, [api_key: "sk-test", retries: 3]}
```

A missing variable returns an error and names it:

```text
%Jido.Error.ValidationError{
  message: "Required environment variable is missing",
  details: %{code: :missing_env, name: "BILLING_API_KEY", path: [:api_key]}
}
```

`resolve/1` reads `System.get_env/1` and works on maps, keyword lists, and
nested values. Jido doesn't load `.env` files. Load them in your host
application before startup.

## What Is Isolated

| Shared or separate | Instance | Partition |
| --- | --- | --- |
| Agent ID space | Separate | Separate |
| Registry, Agent supervisor | Separate | Shared |
| Task supervisor and `max_tasks` | Separate | Shared |
| Workflow runner | Separate | Shared |
| Persistence adapter | Separate | Shared, keyed by partition |
| Agent Server defaults | Separate | Shared |
| BEAM memory, schedulers, atoms | Shared | Shared |
| Action discovery catalog | Shared | Shared |
| Telemetry handlers | Shared | Shared |

A partition separates identity, not resources. One tenant with heavy load
uses the same tasks and schedulers as the others. A partition also isn't
authorization: any code that holds the instance module can start or call an
Agent in any partition. Check access in your application before you route a
Signal to an Agent.

For hard resource limits per tenant, run separate instances, or separate
nodes.

## Next

- [Storage Model](persistence-storage-model.md) – storage records and keys.
- [Deployment and Sizing](deployment-and-performance.md) – supervision,
  shutdown, and limits.
