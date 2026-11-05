# Live Reconfiguration

An Agent can add, configure, or remove a Plugin in a running server. This guide shows the three Directives, the callbacks a runtime Plugin needs, and what happens when a change fails.

## Change a Plugin from a Turn

A handler returns one of these Directives like any other:

| Constructor | Effect |
|---|---|
| `Jido.Agent.Directive.plugin_add/3` | Adds the declaration. The new field starts from the schema default, or from the `:initial` option. |
| `Jido.Agent.Directive.plugin_configure/3` | Replaces the declared options. The option list you pass is complete, so options you leave out are gone. |
| `Jido.Agent.Directive.plugin_remove/2` | Removes the declaration. |

The change is part of the Turn. It commits with the state, or it does not happen. `Jido.Agent.mutate/2` applies the same edits to Agent data without a server. See [Mutations and Diffs](../agents/agent-mutations-and-diffs.livemd).

The change needs an Activation, which `Jido.start_agent/3` provides. Without one, the Turn fails with `:activation_required`.

## Write a replaceable runtime

A running Plugin with `child_spec/1` must define `quiesce/2` and `resume/2` to be configured or removed live. Otherwise the Turn fails with code `:plugin_quiescence_required`. Adding a Plugin needs neither callback, and neither does changing a Plugin that has no runtime process.

Both callbacks take the running process and the options, and return `:ok` or `{:error, reason}`. Both must be safe to call more than once.

- `quiesce/2` stops autonomous work and drains outstanding work before it returns.
- `resume/2` reopens the old process after a rejected change. It must also work when `quiesce/2` did not finish.

This Plugin owns a rate limit counter and a replaceable window process:

```elixir
defmodule LiveReconfigGuide.Window do
  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def info(runtime), do: GenServer.call(runtime, :info)

  @impl true
  def init(init) do
    {:ok, %{limit: init.options[:limit], committed: init.plugin_state, revision: init.state_version, paused: false}}
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, state, state}
  def handle_call(:pause, _from, state), do: {:reply, :ok, %{state | paused: true}}
  def handle_call(:resume, _from, state), do: {:reply, :ok, %{state | paused: false}}
end

defmodule LiveReconfigGuide.RateLimit do
  use Jido.Plugin

  alias LiveReconfigGuide.Window

  @impl true
  def validate_options(opts) do
    if is_integer(opts[:limit]) and opts[:limit] > 0, do: :ok, else: {:error, :invalid_limit}
  end

  @impl true
  def state_spec(_opts), do: {:requests, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}

  @impl true
  def child_spec(init), do: %{id: __MODULE__, start: {Window, :start_link, [init]}}

  @impl true
  def quiesce(runtime, _opts), do: GenServer.call(runtime, :pause)

  @impl true
  def resume(runtime, _opts), do: GenServer.call(runtime, :resume)
end

defmodule LiveReconfigGuide.Gateway do
  use Jido.Agent, name: "gateway"

  alias Jido.Agent.Directive
  alias LiveReconfigGuide.RateLimit

  routes do
    signal_source "/gateway"

    route "gateway.limit.install", as: :install do
      action %{limit: limit}, schema: Jido.Joi.object(%{limit: Jido.Joi.integer()}), context: context do
        {:ok, context.agent_state, [Directive.plugin_add(RateLimit, limit: limit)]}
      end
    end

    route "gateway.limit.set", as: :set_limit do
      action %{limit: limit}, schema: Jido.Joi.object(%{limit: Jido.Joi.integer()}), context: context do
        {:ok, context.agent_state, [Directive.plugin_configure(RateLimit, limit: limit)]}
      end
    end

    route "gateway.limit.remove", as: :remove do
      action %{discard: discard}, schema: Jido.Joi.object(%{discard: Jido.Joi.boolean()}), context: context do
        options = if discard, do: [state: :discard], else: []
        {:ok, context.agent_state, [Directive.plugin_remove(RateLimit, options)]}
      end
    end

    route "gateway.request", as: :request do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

alias Jido.AgentServer, as: Server
alias LiveReconfigGuide.{Gateway, RateLimit, Window}

{:ok, _instance} = Jido.start(name: LiveReconfigGuide.Jido)
{:ok, server} = Jido.start_agent(LiveReconfigGuide.Jido, Gateway, id: "gw-1")
:ok = Server.await_ready(server)

window = fn ->
  case List.keyfind(Supervisor.which_children(Server.activation(server)), {:plugin, RateLimit}, 0) do
    {_id, pid, _kind, _modules} when is_pid(pid) -> pid
    _none -> nil
  end
end

{:ok, installed, [_add]} = Server.call(server, Gateway.install_signal!(%{limit: 10}))
:ok = Server.await_ready(server)

first = window.()
%{limit: 10, committed: 0, revision: 1} = Window.info(first)
%{requests: 0} = installed.state
```

Installing returned `requests: 0` because the reducer did not run for a Plugin added in that Turn. The process started from revision 1. Call `Jido.AgentServer.await_ready/2` after a change and before you rely on the new process, because the reply arrives at commit.

## Replace the runtime

Configuring pauses the old process, commits the change, stops the old process, and starts a new one from the committed state. The Plugin's field carries over. Its reducer ran on both Turns below, so the new process starts with a count of 2.

```elixir
alias Jido.AgentServer, as: Server
alias LiveReconfigGuide.{Gateway, Window}

{:ok, _, _} = Server.call(server, Gateway.request_signal!(%{}))

{:ok, _, _} = Server.call(server, Gateway.set_limit_signal!(%{limit: 50}))
:ok = Server.await_ready(server)

second = window.()
true = second != first
false = Process.alive?(first)
%{limit: 50, committed: 2, revision: 3, paused: false} = Window.info(second)
```

The sequence of one change is:

1. The handler returns the Directive, and Jido validates the new declarations, including `validate_options/1`.
2. `quiesce/2` runs for each changed Plugin with a runtime. Each call has 5,000 milliseconds.
3. The server saves when it has persistence configured, and then commits. The caller receives its result.
4. The server stops each changed process and starts its replacement from `Jido.Plugin.Init`, within `readiness_timeout`.
5. `after_commit/3` runs for unchanged Plugins, and then Directives run.

New, changed, and removed Plugins do not receive `after_commit/3` for that commit. Their replacement reads the same data from `Jido.Plugin.Init`, so a runtime must be able to start from that value alone.

## Failed changes

A change that fails before commit leaves the Agent and the running process in place.

```elixir
alias Jido.AgentServer, as: Server
alias LiveReconfigGuide.{Gateway, Window}

before = Server.snapshot(server)

{:error, :invalid_limit} = Server.call(server, Gateway.set_limit_signal!(%{limit: 0}))
^before = Server.snapshot(server)
^second = window.()
%{paused: false} = Window.info(second)
```

| When it fails | Result |
|---|---|
| Invalid declaration or options | The Turn fails. `quiesce/2` never ran. |
| `quiesce/2` returns an error or times out | The Turn fails, and `resume/2` reopens the old process. |
| The Turn is cancelled during the pause | The Turn fails with `:cancelled`, and `resume/2` reopens the old process. |
| `resume/2` fails | The Activation stops. |
| The save fails after the pause | The Activation stops, because the commit is uncertain. |
| The replacement cannot start or is not ready in time | The commit stands, and the Activation stops. |

A Turn also fails with `:plugin_change_with_owned_directive` when its batch changes a Plugin and includes that Plugin's own Directive.

## Migrate or discard state

Removing a Plugin that owns state requires an explicit decision, because its data would be lost. Pass `state: :discard`.

```elixir
alias Jido.AgentServer, as: Server
alias LiveReconfigGuide.Gateway

{:error, %{code: :plugin_state_discard_required}} = Server.call(server, Gateway.remove_signal!(%{discard: false}))
^second = window.()

{:ok, removed, _} = Server.call(server, Gateway.remove_signal!(%{discard: true}))
:ok = Server.await_ready(server)

nil = window.()
false = Map.has_key?(removed.state, :requests)
:ok = Jido.stop_agent(LiveReconfigGuide.Jido, server)
```

`plugin_configure/3` keeps the field's value by default. Pass `migrate: {module, function, args}` to transform it. The function receives the old value first and returns `{:ok, value}` or `{:error, reason}`. The option is required when the new options change the state key. Otherwise the change fails with `:plugin_migration_required`. A migration must leave a value that the new schema accepts.

```elixir
defmodule LiveReconfigGuide.Quota do
  use Jido.Plugin, option_keys: [agent: [:unit]]

  @impl true
  def state_spec(opts) do
    key = if opts[:unit] == :minutes, do: :quota_minutes, else: :quota_seconds
    {key, Jido.Joi.integer() |> Jido.Joi.default(0)}
  end

  def to_minutes(seconds), do: {:ok, div(seconds, 60)}
end

alias Jido.Agent.Directive
alias LiveReconfigGuide.Gateway

{:ok, quota_agent, _diff} =
  Gateway.instantiate!(id: "gw-2")
  |> Jido.Agent.mutate([Directive.plugin_add(LiveReconfigGuide.Quota, [unit: :seconds], initial: 180)])

%{quota_seconds: 180} = quota_agent.state

{:error, %{code: :plugin_migration_required}} =
  Jido.Agent.mutate(quota_agent, [Directive.plugin_configure(LiveReconfigGuide.Quota, unit: :minutes)])

{:ok, migrated, _diff} =
  Jido.Agent.mutate(quota_agent, [
    Directive.plugin_configure(LiveReconfigGuide.Quota, [unit: :minutes],
      migrate: {LiveReconfigGuide.Quota, :to_minutes, []}
    )
  ])

%{quota_minutes: 3} = migrated.state
```

## Restart and thaw

The accepted declaration is part of the Agent, so it survives a restart. With persistence configured, a thawed server starts the runtime from the saved options, state, and revision. It does not replay `after_commit/3`.

## Next steps

- [Supervised Resources](plugin-supervised-resources.livemd) covers the runtime process.
- [Change Live Composition](../composition/change-live-composition.md) covers topology changes in a Turn.
- [Upgrade Live Agents](../agent-servers/upgrade-live-agents.md) covers code changes.
