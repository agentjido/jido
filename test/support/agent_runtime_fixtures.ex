defmodule JidoTest.AgentRuntimeFixtures.ReturnDirective do
  @moduledoc false
  use Jido.Action, name: "agent_return_directive"

  @impl Jido.Action
  def run(%{event: event} = params, context) do
    state = context.agent_state
    directives = Map.get(params, :directives) || [Map.fetch!(params, :directive)]
    {:ok, %{state | events: state.events ++ [event]}, directives}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.Record do
  @moduledoc false
  use Jido.Action, name: "agent_runtime_record"

  @impl Jido.Action
  def run(params, context) do
    event = Map.get(params, :event, params)
    state = context.agent_state
    {:ok, %{state | events: state.events ++ [event]}}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.Tick do
  @moduledoc false
  use Jido.Action, name: "agent_runtime_tick"

  @impl Jido.Action
  def run(_params, context) do
    state = context.agent_state
    {:ok, %{state | ticks: state.ticks + 1}}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.ReplyToParent do
  @moduledoc false
  use Jido.Action, name: "agent_reply_to_parent"

  alias Jido.Agent.Directive

  @impl Jido.Action
  def run(%{reply: reply} = params, context) do
    state = context.agent_state
    next_state = %{state | events: state.events ++ [Map.get(params, :event, :ping)]}
    {:ok, next_state, [Directive.emit_to_parent(reply)]}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.BootPluginWorker do
  @moduledoc false

  use GenServer

  alias Jido.Signal

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(%{agent_server: agent_server}) do
    signal =
      Signal.new!(
        "runtime.plugin.boot",
        %{event: :plugin_booted},
        source: "/plugin/runtime"
      )

    send(agent_server, {:signal, signal})
    {:ok, %{agent_server: agent_server}}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.BootPlugin do
  @moduledoc false

  use Jido.Plugin

  alias JidoTest.AgentRuntimeFixtures.BootPluginWorker

  @impl Jido.Plugin
  def state_spec(_opts) do
    {:boot, Zoi.object(%{calls: Zoi.integer() |> Zoi.default(0)}) |> Zoi.default(%{calls: 0})}
  end

  @impl Jido.Plugin
  def update_state(state, _directives, _opts) do
    {:ok, Map.update!(state, :calls, &(&1 + 1))}
  end

  def child_spec(init) do
    Supervisor.child_spec({BootPluginWorker, init}, id: __MODULE__)
  end
end

defmodule JidoTest.AgentRuntimeFixtures.RuntimeAgent do
  @moduledoc false

  alias JidoTest.AgentRuntimeFixtures.{Record, ReturnDirective, Tick}

  use Jido.Agent,
    name: "runtime_agent",
    schema:
      Zoi.object(%{
        events: Zoi.list(Zoi.any()) |> Zoi.default([]),
        ticks: Zoi.integer() |> Zoi.default(0)
      }),
    routes: [
      {"runtime.directive", ReturnDirective},
      {"runtime.record", Record},
      {"cron.tick", Tick},
      {"jido.agent.child.started", Record},
      {"jido.agent.child.exit", Record},
      {"jido.agent.orphaned", Record}
    ],
    plugins: [Jido.Plugin.Scheduler]
end

defmodule JidoTest.AgentRuntimeFixtures.ChildAgent do
  @moduledoc false

  alias JidoTest.AgentRuntimeFixtures.{Record, ReplyToParent}

  use Jido.Agent,
    name: "runtime_child_agent",
    schema: Zoi.object(%{events: Zoi.list(Zoi.any()) |> Zoi.default([])}),
    routes: [
      {"child.record", Record},
      {"child.reply", ReplyToParent},
      {"jido.agent.orphaned", Record}
    ]
end

defmodule JidoTest.AgentRuntimeFixtures.PluginRuntimeAgent do
  @moduledoc false

  alias JidoTest.AgentRuntimeFixtures.{BootPlugin, Record}

  use Jido.Agent,
    name: "plugin_runtime_agent",
    schema:
      Zoi.object(%{
        events: Zoi.list(Zoi.any()) |> Zoi.default([])
      }),
    routes: [{"runtime.plugin.boot", Record}],
    plugins: [BootPlugin]
end
