> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Jido instance

[Design overview](README.md) | Previous: [Agent Server](agent-server.md) | Next: [Commit and effects](commit-and-effects.md)

- Depends on: OTP and Agent Server.
- Defines: the application-owned Jido supervisor, instance identity, config,
  and public runtime facade.

## Definition

An application defines one Jido instance module:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary"
end
```

It starts that module in its application supervision tree:

```elixir
children = [MyApp.Jido]
```

`MyApp.Jido` has three roles:

1. It is the registered local name and owns one stable instance namespace.
2. It is the OTP supervisor for that instance.
3. It is the application-facing API for Agent lifecycle operations.

It does not contain Agent domain state or application business logic.

`namespace` is the stable instance identity used in Agent Refs and durable
records. The module is the local OTP name. Each instance must use a unique,
non-empty namespace.

## Startup and link ownership

Agent startup belongs to the Jido instance API. In the current SDK:

```elixir
{:ok, server} = MyApp.Jido.start_agent(Counter, id: "counter-1")
{:ok, server} = Jido.start_agent(jido, Counter, id: "counter-1")
```

The Server links to the instance supervisor. The original caller can exit
without stopping it. `Jido.AgentServer.start_link/1` instead links the Server
to its calling process. The planned Ref-based API below preserves this ownership
rule; its return shape is separate from the current PID-based API.

Startup options must be a keyword list. An omitted ID generates a new identity;
a supplied ID must be a nonempty string. A live ID is unique within its instance
and partition. Duplicate startup returns an error and leaves the existing Agent
unchanged. An existing Agent value keeps its ID and rejects instance overrides.
Validation errors use structured errors at the shared startup boundary.

## OTP shape

```text
MyApp.Application.Supervisor
└── MyApp.Jido                         :rest_for_one
    ├── MyApp.Jido.Registry            Registry
    ├── MyApp.Jido.TaskSupervisor      short work
    ├── MyApp.Jido.PluginRuntimePool   DynamicSupervisor
    └── MyApp.Jido.AgentPool           DynamicSupervisor
```

Child order records dependencies. If Registry or task supervision is lost,
later pools restart. Failure of one Agent Server stays inside `AgentPool`.
Failure of one Plugin runtime stays inside `PluginRuntimePool`. Its host reports
the failure to the Agent Server. The Server supplies a fresh Init from the
latest committed Plugin state and Agent state version for replacement.

The application supervises external resources, such as an Ecto Repo or Redis
connection. These resources are not hidden inside the Jido instance. A resource
used by persistence starts before the Jido instance:

```elixir
children = [MyApp.Repo, MyApp.Jido]
```

## Configuration

`otp_app` and `namespace` are required. Runtime configuration is scoped by both
the OTP application and the instance module:

```elixir
config :my_app, MyApp.Jido,
  max_tasks: 1_000,
  persistence_timeout: 5_000
```

Options given to `child_spec/1` or `start_link/1` override application config.
The instance validates its complete config before it starts children.

The resolved configuration is a Zoi-backed public value:

```elixir
%Jido.Instance.Config{
  otp_app: :my_app,
  module: MyApp.Jido,
  namespace: "my-app/primary",
  max_tasks: 1_000,
  persistence_timeout: 5_000,
  observability: %{
    log: :errors,
    slow_turn_ms: 1_000,
    slow_directive_ms: 1_000
  }
}
```

`Jido.Instance.Config` has one purpose: it is the complete effective runtime
configuration for one Jido instance. Keyword options and application config
are inputs. `config/1` normalizes them and returns this struct. The nested
observability Map has a closed Zoi object schema; it is not an independent
public value.

## Generated API

`use Jido` generates a thin module API:

```elixir
MyApp.Jido.child_spec(opts \\ [])
MyApp.Jido.start_link(opts \\ [])
MyApp.Jido.config(overrides \\ [])
MyApp.Jido.agent_ref(agent_id, opts \\ [])

MyApp.Jido.start_agent(agent_module_or_agent, opts \\ [])
MyApp.Jido.activate_agent(agent_ref, opts \\ [])
MyApp.Jido.call(agent_ref, signal, opts \\ [])
MyApp.Jido.cast(agent_ref, signal, opts \\ [])
MyApp.Jido.send_request(agent_ref, signal, opts \\ [])
MyApp.Jido.receive_response(request_id, timeout \\ 5_000)
MyApp.Jido.cancel(agent_ref, opts \\ [])
MyApp.Jido.cancel_turn(agent_ref, turn_id, opts \\ [])
MyApp.Jido.stop_agent(agent_ref, opts \\ [])
MyApp.Jido.whereis_local(agent_ref, opts \\ [])
MyApp.Jido.list_agents(opts \\ [])
MyApp.Jido.agent_count(opts \\ [])
MyApp.Jido.hibernate(agent_ref, opts \\ [])
MyApp.Jido.thaw(agent_ref, opts \\ [])
MyApp.Jido.delete_agent(agent_ref, opts \\ [])
MyApp.Jido.agent(agent_ref, opts \\ [])
MyApp.Jido.plugin_state(agent_ref, plugin_id, opts \\ [])
MyApp.Jido.status(agent_ref, opts \\ [])
MyApp.Jido.commit(agent_ref, opts \\ [])
MyApp.Jido.plugin_runtimes(agent_ref, opts \\ [])
MyApp.Jido.attach_agent(agent_ref, owner_pid \\ self(), opts \\ [])
MyApp.Jido.detach_agent(agent_ref, owner_pid \\ self(), opts \\ [])
MyApp.Jido.touch_agent(agent_ref, opts \\ [])
```

The functions delegate to Jido internals with `MyApp.Jido` as the instance
identity. Applications do not call internal supervisor names in normal code.
`start_agent/2` creates a new Agent and returns its Agent Ref. A persistent
create waits for provisional Plugin runtime readiness before it writes its
initial active Record. A readiness failure writes no Record. Creation also
fails when a durable Record already exists. `activate_agent/2` restores an
active durable Record. Instance operations accept the Ref and resolve its
current local runtime. `whereis_local/2` is an explicit local observation
function and returns a PID or nil.

`cast/3` is a best-effort send to the currently resolved local Server. Its
`:ok` return does not confirm admission, execution, or commit. Applications
that need a command Result use `call/3` or the asynchronous request API.

`Jido.AgentServer` is internal. The instance facade resolves the Agent Ref,
normalizes public errors, and applies one lookup and timeout policy. A PID from
`whereis_local/2` is local observation only; it does not create a second
supported command API.

The instance can also implement the optional persistence contract described in
[Instance persistence](instance-persistence.md).

## Multiple instances

An application can define several instance modules. Each module has separate
configuration, names, pools, Registry entries, and persistence scope:

```elixir
defmodule MyApp.PrimaryJido do
  use Jido, otp_app: :my_app, namespace: "my-app/primary"
end

defmodule MyApp.BatchJido do
  use Jido, otp_app: :my_app, namespace: "my-app/batch"
end
```

Agent identity includes its Jido instance namespace. Equal Agent IDs in
different instances do not conflict.

## Rules

- The application supervises each Jido instance.
- The instance module is the public runtime facade.
- Public instance operations address Agents with `Jido.Agent.Ref`.
- Agent Server functions and messages are internal implementation contracts.
- Every Agent Server belongs to one Agent Pool and one Jido instance.
- Plugin runtime hosts never enter the Agent Pool.
- Instance restart does not make runtime state durable.
- A persistent Agent Server restart loads its latest durable Record.
- A nonpersistent Agent Server restart resets to the complete initial Agent
  preserved by its child specification.
- Persistence is optional and belongs to the instance contract.
