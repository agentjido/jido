defmodule Jido.PluginRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Command
  alias Jido.Plugin
  alias Jido.Signal

  defmodule AddAction do
    use Jido.Action, name: "agent_runtime_plugin_add"

    @impl Jido.Action
    def run(%{amount: amount}, %{agent_state: state}) do
      {:ok, %{state | count: state.count + amount}}
    end
  end

  defmodule MiddlewareOnlyPlugin do
    use Jido.Plugin

    @impl Plugin
    def prepare(%Command{} = command, _opts), do: {:ok, command}
  end

  defmodule RuntimePlugin do
    use Jido.Plugin

    @impl Plugin
    def state_spec(_opts) do
      {:runtime,
       Zoi.object(%{calls: Zoi.integer() |> Zoi.default(0)}) |> Zoi.default(%{calls: 0})}
    end

    @impl Plugin
    def update_state(state, _directives, _opts) do
      {:ok, %{state | calls: state.calls + 1}}
    end

    def child_spec(init) do
      Supervisor.child_spec(
        {Jido.PluginRuntimeTest.RuntimeTree, init},
        id: __MODULE__
      )
    end
  end

  defmodule ProcessPlugin do
    use GenServer

    use Jido.Plugin

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl GenServer
    def init(init) do
      send(Keyword.fetch!(init.options, :test), {:process_plugin_started, self(), init})
      {:ok, init}
    end
  end

  defmodule TemporaryRuntimePlugin do
    use Jido.Plugin

    def child_spec(init) do
      %{
        id: __MODULE__,
        start: {Jido.PluginRuntimeTest.ProcessPlugin, :start_link, [init]},
        restart: :temporary,
        type: :worker
      }
    end
  end

  defmodule InvalidRuntimePlugin do
    use Jido.Plugin

    def child_spec(_init), do: %{id: __MODULE__}
  end

  defmodule RaisingRuntimePlugin do
    use Jido.Plugin

    def child_spec(_init), do: raise("invalid runtime configuration")
  end

  defmodule RuntimeAgent do
    use Agent,
      name: "runtime_plugin_agent",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0)
        }),
      routes: [{"counter.add", AddAction}],
      plugins: [RuntimePlugin]
  end

  defmodule AgentHost do
    use GenServer

    def start_link({%Agent{} = agent, test_pid}) do
      GenServer.start_link(__MODULE__, {agent, test_pid})
    end

    def signal(server, %Signal{} = signal), do: GenServer.cast(server, {:signal, signal})
    def agent(server), do: GenServer.call(server, :agent)

    @impl GenServer
    def init(state), do: {:ok, state}

    @impl GenServer
    def handle_call(:agent, _from, {agent, test_pid}) do
      {:reply, agent, {agent, test_pid}}
    end

    @impl GenServer
    def handle_cast({:signal, signal}, {agent, test_pid}) do
      case Agent.cmd(agent, signal) do
        {:ok, next_agent, directives} ->
          send(test_pid, {:agent_committed, next_agent, directives})
          {:noreply, {next_agent, test_pid}}

        {:error, reason} ->
          send(test_pid, {:agent_failed, reason})
          {:noreply, {agent, test_pid}}
      end
    end
  end

  defmodule RuntimeTree do
    use Supervisor

    def start_link(init), do: Supervisor.start_link(__MODULE__, init)

    @impl Supervisor
    def init(init) do
      Supervisor.init([{Jido.PluginRuntimeTest.RuntimeWorker, init}],
        strategy: :one_for_one
      )
    end
  end

  defmodule RuntimeWorker do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)
    def emit(server, %Signal{} = signal), do: GenServer.cast(server, {:emit, signal})

    @impl GenServer
    def init(init) do
      send(Keyword.fetch!(init.options, :test), {:runtime_started, self(), init})
      {:ok, init}
    end

    @impl GenServer
    def handle_cast({:emit, signal}, init) do
      AgentHost.signal(init.agent_server, signal)
      {:noreply, init}
    end
  end

  defmodule RuntimeRoot do
    use Supervisor

    def start_link(children), do: Supervisor.start_link(__MODULE__, children)

    @impl Supervisor
    def init(children), do: Supervisor.init(children, strategy: :one_for_one)
  end

  setup do
    agent = RuntimeAgent.new!()
    agent_host = start_supervised!({AgentHost, {agent, self()}})

    init = %Plugin.Init{
      agent_server: agent_host,
      agent_id: agent.id,
      module: nil,
      options: [],
      jido: nil
    }

    %{agent: agent, agent_host: agent_host, init: init}
  end

  test "middleware-only Plugins add no runtime child", %{init: init} do
    assert {:ok, []} = Plugin.child_specs(init, [MiddlewareOnlyPlugin])
  end

  test "public Plugin runtime structs expose Zoi schemas" do
    assert %Zoi.Types.Struct{module: Plugin.Init} = Plugin.Init.schema()

    assert %Zoi.Types.Struct{module: Plugin.DirectiveContext} =
             Plugin.DirectiveContext.schema()
  end

  test "uses the standard child_spec/1 interface", %{agent_host: agent_host, init: init} do
    opts = [test: self(), label: :clock]

    assert {:ok, [spec]} = Plugin.child_specs(init, [{RuntimePlugin, opts}])
    assert spec.id == RuntimePlugin
    assert spec.type == :supervisor

    _runtime_root = start_supervised!({RuntimeRoot, [spec]})

    assert_receive {:runtime_started, worker, init}
    assert is_pid(worker)

    assert %Plugin.Init{
             agent_server: ^agent_host,
             agent_id: agent_id,
             module: RuntimePlugin,
             options: ^opts
           } = init

    assert is_binary(agent_id)

    refute match?(%Agent{}, init.agent_server)
  end

  test "a Plugin can also be the supervised OTP process", %{agent_host: agent_host, init: init} do
    opts = [test: self()]

    assert {:ok, [spec]} = Plugin.child_specs(init, [{ProcessPlugin, opts}])
    assert spec.id == ProcessPlugin
    assert Map.get(spec, :type, :worker) == :worker

    _runtime_root = start_supervised!({RuntimeRoot, [spec]})

    assert_receive {:process_plugin_started, process, init}
    assert Process.alive?(process)

    assert %Plugin.Init{
             agent_server: ^agent_host,
             agent_id: agent_id,
             module: ProcessPlugin,
             options: ^opts
           } = init

    assert is_binary(agent_id)
  end

  test "requires a permanent Plugin runtime root", %{init: init} do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Plugin.child_specs(init, [TemporaryRuntimePlugin])

    assert message == "Agent Plugin runtime root must use :permanent restart"
  end

  test "a runtime child sends a Signal through the Agent command path", %{
    agent_host: agent_host,
    init: init
  } do
    opts = [test: self()]
    {:ok, specs} = Plugin.child_specs(init, [{RuntimePlugin, opts}])
    _runtime_root = start_supervised!({RuntimeRoot, specs})

    assert_receive {:runtime_started, worker, _init}

    signal = Signal.new!("counter.add", %{amount: 2}, source: "/runtime-plugin")
    RuntimeWorker.emit(worker, signal)

    assert_receive {:agent_committed, next_agent, []}, 1_000
    assert next_agent.state == %{count: 2, runtime: %{calls: 1}}
    assert AgentHost.agent(agent_host) == next_agent
  end

  test "a runtime worker restart does not replace Agent state", %{
    init: init
  } do
    opts = [test: self()]
    {:ok, specs} = Plugin.child_specs(init, [{RuntimePlugin, opts}])
    _runtime_root = start_supervised!({RuntimeRoot, specs})

    assert_receive {:runtime_started, worker, _init}

    RuntimeWorker.emit(
      worker,
      Signal.new!("counter.add", %{amount: 2}, source: "/runtime-plugin")
    )

    assert_receive {:agent_committed, first_agent, []}
    assert first_agent.state == %{count: 2, runtime: %{calls: 1}}

    monitor = Process.monitor(worker)
    Process.exit(worker, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert_receive {:runtime_started, restarted_worker, _init}
    refute restarted_worker == worker

    RuntimeWorker.emit(
      restarted_worker,
      Signal.new!("counter.add", %{amount: 3}, source: "/runtime-plugin")
    )

    assert_receive {:agent_committed, second_agent, []}
    assert second_agent.state == %{count: 5, runtime: %{calls: 2}}
  end

  test "rejects a repeated Plugin module", %{init: init} do
    declarations = [
      {RuntimePlugin, test: self(), label: :first},
      MiddlewareOnlyPlugin,
      {RuntimePlugin, test: self(), label: :second}
    ]

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Plugin.child_specs(init, declarations)

    assert message == "Agent Plugin modules must be unique"
  end

  test "rejects an invalid runtime child specification", %{init: init} do
    assert {:error, %Jido.Error.ValidationError{}} =
             Plugin.child_specs(init, [InvalidRuntimePlugin])
  end

  test "contains a failure from child_spec/1", %{init: init} do
    assert {:error, %Jido.Error.ValidationError{}} =
             Plugin.child_specs(init, [RaisingRuntimePlugin])
  end
end
