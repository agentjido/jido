defmodule Jido.Plugin.RuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Plugin
  alias Jido.Signal

  defmodule AddAction do
    use Jido.Action, name: "agent_runtime_plugin_add"

    @impl Jido.Action
    def run(%{amount: amount}, %{agent_state: state}) do
      {:ok, %{state | count: state.count + amount}}
    end
  end

  defmodule RuntimePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule RuntimePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts) do
      {:runtime,
       Zoi.object(%{calls: Zoi.integer() |> Zoi.default(0)}) |> Zoi.default(%{calls: 0})}
    end

    @impl true
    def reduce(reduction, _opts) do
      {:ok, %{reduction.plugin_state | calls: reduction.plugin_state.calls + 1}}
    end
  end

  defmodule RuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    def child_spec(init) do
      Supervisor.child_spec(
        {Jido.Plugin.RuntimeTest.RuntimeTree, init},
        id: RuntimePlugin
      )
    end
  end

  defmodule ProcessPlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server

    def start_link(init), do: GenServer.start_link(__MODULE__.Process, init)
  end

  defmodule ProcessPlugin.Server do
    use Jido.AgentServer.Plugin
    def child_spec(init), do: %{id: ProcessPlugin, start: {ProcessPlugin, :start_link, [init]}}
  end

  defmodule ProcessPlugin.Process do
    use GenServer

    @impl GenServer
    def init(init) do
      send(
        Jido.Plugin.RuntimeTest.observer(init.options),
        {:process_plugin_started, self(), init}
      )

      {:ok, init}
    end
  end

  defmodule TemporaryRuntimePlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule TemporaryRuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    def child_spec(init) do
      %{
        id: TemporaryRuntimePlugin,
        start: {Jido.Plugin.RuntimeTest.ProcessPlugin, :start_link, [init]},
        restart: :temporary,
        type: :worker
      }
    end
  end

  defmodule InvalidRuntimePlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule InvalidRuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    def child_spec(_init), do: %{id: InvalidRuntimePlugin}
  end

  defmodule RaisingRuntimePlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule RaisingRuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    def child_spec(_init), do: raise("invalid runtime configuration")
  end

  defmodule ConfigurableRuntimePlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule ConfigurableRuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    def child_spec(%Plugin.Init{options: opts}) do
      :persistent_term.get(
        {ConfigurableRuntimePlugin, :child_spec, Keyword.fetch!(opts, :spec_key)}
      )
    end
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
      Supervisor.init([{Jido.Plugin.RuntimeTest.RuntimeWorker, init}],
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
      send(Jido.Plugin.RuntimeTest.observer(init.options), {:runtime_started, self(), init})
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
    observer_key = System.unique_integer([:positive])
    :persistent_term.put({__MODULE__, :observer, observer_key}, self())
    Process.put({__MODULE__, :observer_key}, observer_key)
    on_exit(fn -> :persistent_term.erase({__MODULE__, :observer, observer_key}) end)

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

  def observer(opts),
    do: :persistent_term.get({__MODULE__, :observer, Keyword.fetch!(opts, :test)})

  test "public Plugin runtime structs expose Zoi schemas" do
    assert %Zoi.Types.Struct{module: Plugin.Init} = Plugin.Init.schema()

    assert %Zoi.Types.Struct{module: Plugin.DirectiveContext} =
             Plugin.DirectiveContext.schema()
  end

  test "uses the standard child_spec/1 interface", %{agent_host: agent_host, init: init} do
    opts = [test: Process.get({__MODULE__, :observer_key}), label: :clock]

    assert {:ok, [spec]} =
             Jido.AgentServer.Plugin.Callbacks.child_specs(init, [{RuntimePlugin, opts}])

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

  test "a Plugin package can own a separate supervised OTP process", %{
    agent_host: agent_host,
    init: init
  } do
    opts = [test: Process.get({__MODULE__, :observer_key})]

    assert {:ok, [spec]} =
             Jido.AgentServer.Plugin.Callbacks.child_specs(init, [{ProcessPlugin, opts}])

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
             Jido.AgentServer.Plugin.Callbacks.child_specs(init, [TemporaryRuntimePlugin])

    assert message == "Agent Server Plugin runtime root must use :permanent restart"
  end

  test "a runtime child sends a Signal through the Agent command path", %{
    agent_host: agent_host,
    init: init
  } do
    opts = [test: Process.get({__MODULE__, :observer_key})]
    {:ok, specs} = Jido.AgentServer.Plugin.Callbacks.child_specs(init, [{RuntimePlugin, opts}])
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
    opts = [test: Process.get({__MODULE__, :observer_key})]
    {:ok, specs} = Jido.AgentServer.Plugin.Callbacks.child_specs(init, [{RuntimePlugin, opts}])
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
      {RuntimePlugin, test: Process.get({__MODULE__, :observer_key}), label: :first},
      ProcessPlugin,
      {RuntimePlugin, test: Process.get({__MODULE__, :observer_key}), label: :second}
    ]

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.AgentServer.Plugin.Callbacks.child_specs(init, declarations)

    assert message == "Agent Plugin modules must be unique"
  end

  test "rejects an invalid runtime child specification", %{init: init} do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.AgentServer.Plugin.Callbacks.child_specs(init, [InvalidRuntimePlugin])
  end

  test "validates all OTP child specification fields before startup", %{init: init} do
    base = %{id: :runtime, start: {ProcessPlugin, :start_link, [init]}}

    invalid_specs = [
      %{base | start: {ProcessPlugin, :start_link, :invalid}},
      Map.put(base, :restart, :sometimes),
      Map.put(base, :shutdown, :later),
      Map.put(base, :type, :process),
      Map.put(base, :modules, :all),
      Map.put(base, :significant, :yes),
      %{base | start: {JidoTest.MissingRuntime, :start_link, [init]}},
      %{base | start: {ProcessPlugin, :missing_start, [init]}}
    ]

    for child_spec <- invalid_specs do
      spec_key = System.unique_integer([:positive])
      :persistent_term.put({ConfigurableRuntimePlugin, :child_spec, spec_key}, child_spec)

      assert {:error, %Jido.Error.ValidationError{} = error} =
               Jido.AgentServer.Plugin.Callbacks.child_specs(init, [
                 {ConfigurableRuntimePlugin, spec_key: spec_key}
               ])

      :persistent_term.erase({ConfigurableRuntimePlugin, :child_spec, spec_key})

      assert error.message ==
               "Agent Server Plugin child_spec/1 returned an invalid child specification"

      assert error.details.plugin == ConfigurableRuntimePlugin
      assert Map.has_key?(error.details, :reason)
    end
  end

  test "contains a failure from child_spec/1", %{init: init} do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.AgentServer.Plugin.Callbacks.child_specs(init, [RaisingRuntimePlugin])
  end
end
