defmodule Jido.AgentServer.PluginBoundaryTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{PluginChild, PluginLifecycle}
  alias Jido.Plugin.Init

  defmodule Runtime do
    use GenServer
    use Jido.Plugin

    def child_spec(init) do
      if Keyword.get(init.options, :invalid_spec),
        do: raise(ArgumentError, "invalid runtime spec")

      %{id: __MODULE__, start: {__MODULE__, :start_link, [init]}}
    end

    def start_link(init) do
      case Keyword.get(init.options, :start, :ok) do
        :ignore ->
          :ignore

        :error ->
          {:error, :runtime_unavailable}

        :info ->
          {:ok, pid} = GenServer.start_link(__MODULE__, init)
          {:ok, pid, :started}

        :ok ->
          GenServer.start_link(__MODULE__, init)
      end
    end

    def init(init), do: {:ok, init}
  end

  defmodule StateOnly do
    use Jido.Plugin
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
  end

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  for registration <- [:unnamed, nil, :registry] do
    test "wrapper starts and stops its runtime with #{registration} registration", %{jido: jido} do
      name = {:via, Registry, {Jido.registry_name(jido), {:plugin_boundary, self()}}}

      extra =
        case unquote(registration) do
          :unnamed -> []
          nil -> [nil]
          :registry -> [name]
        end

      {wrapper, runtime, _init, _spec} = start_wrapper(extra)
      assert PluginChild.child_pid(wrapper) == runtime
      assert :sys.get_state(runtime).agent_server == self()

      if unquote(registration) == :registry do
        assert PluginChild.child_pid(name) == runtime
      end

      runtime_ref = Process.monitor(runtime)
      wrapper_ref = Process.monitor(wrapper)
      assert :ok = stop_supervised(PluginChild)
      assert_receive {:DOWN, ^wrapper_ref, :process, ^wrapper, :shutdown}, 1_000
      assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :shutdown}, 1_000
    end
  end

  test "a rejected replacement bootstrap stops the wrapper and its supervisor" do
    {wrapper, runtime, _init, _spec} = start_wrapper()
    supervisor = :sys.get_state(wrapper).supervisor
    wrapper_ref = Process.monitor(wrapper)
    supervisor_ref = Process.monitor(supervisor)
    token = request_restart(wrapper, runtime)

    send(wrapper, {:plugin_runtime_bootstrap, token, {:error, :replacement_rejected}})

    assert_receive {:DOWN, ^wrapper_ref, :process, ^wrapper,
                    {:plugin_runtime_bootstrap_failed, Runtime, :killed, :replacement_rejected}},
                   1_000

    assert_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, :shutdown}, 1_000
  end

  test "a replacement runtime can return additional startup information" do
    {wrapper, runtime, init, _spec} = start_wrapper()
    token = request_restart(wrapper, runtime)
    replacement = Runtime.child_spec(%{init | options: [start: :info]})
    send(wrapper, {:plugin_runtime_bootstrap, token, {:ok, replacement}})

    assert_receive {:plugin_runtime_ready, ^wrapper, Runtime, next_runtime}, 1_000
    assert is_pid(next_runtime)
    assert next_runtime != runtime
    assert PluginChild.child_pid(wrapper) == next_runtime
    assert :sys.get_state(next_runtime).options == [start: :info]
  end

  test "an ignored replacement runtime stops the wrapper" do
    {wrapper, runtime, init, _spec} = start_wrapper()
    wrapper_ref = Process.monitor(wrapper)
    token = request_restart(wrapper, runtime)
    replacement = Runtime.child_spec(%{init | options: [start: :ignore]})
    send(wrapper, {:plugin_runtime_bootstrap, token, {:ok, replacement}})

    assert_receive {:DOWN, ^wrapper_ref, :process, ^wrapper,
                    {:plugin_runtime_restart_ignored, Runtime, :killed}},
                   1_000
  end

  test "a failed replacement start stops the wrapper with its original exit reason" do
    {wrapper, runtime, init, _spec} = start_wrapper()
    wrapper_ref = Process.monitor(wrapper)
    token = request_restart(wrapper, runtime)
    replacement = Runtime.child_spec(%{init | options: [start: :error]})
    send(wrapper, {:plugin_runtime_bootstrap, token, {:ok, replacement}})

    assert_receive {:DOWN, ^wrapper_ref, :process, ^wrapper,
                    {:plugin_runtime_restart_failed, Runtime, :killed, reason}},
                   1_000

    assert {:runtime_unavailable, _child_spec} = reason
  end

  test "loss of the runtime supervisor stops the wrapper and runtime" do
    {wrapper, runtime, _init, _spec} = start_wrapper()
    supervisor = :sys.get_state(wrapper).supervisor
    wrapper_ref = Process.monitor(wrapper)
    runtime_ref = Process.monitor(runtime)
    Process.exit(supervisor, :kill)

    assert_receive {:DOWN, ^wrapper_ref, :process, ^wrapper, {:plugin_supervisor_exit, :killed}},
                   1_000

    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :killed}, 1_000
  end

  test "replacement lookup distinguishes an absent Plugin from a Plugin without a runtime" do
    definition = Jido.Agent.new!(name: "state_only_plugin", plugins: [StateOnly])
    server = start_supervised!({Server, agent: definition})
    assert :ok = Server.await_ready(server)
    {:idle, state} = :sys.get_state(server)

    assert {:error, {:plugin_spec_not_found, Runtime}} =
             PluginLifecycle.replacement_child_spec(state, Runtime)

    assert {:error, {:plugin_runtime_not_declared, StateOnly}} =
             PluginLifecycle.replacement_child_spec(state, StateOnly)

    assert PluginLifecycle.readiness_status(state) == :ready
    assert Server.agent(server).state == %{owned: 0}
  end

  test "an invalid child specification fails startup before any runtime exists" do
    definition =
      Jido.Agent.new!(name: "invalid_runtime_spec", plugins: [{Runtime, invalid_spec: true}])

    assert {:ok, server} = Server.start_link(agent: definition)

    assert_receive {:EXIT, ^server,
                    {:shutdown, {:bootstrap_failed, {:plugin_child_specs_failed, error}}}},
                   1_000

    assert %Jido.Error.ValidationError{details: %{plugin: Runtime, error: %ArgumentError{}}} =
             error
  end

  test "standalone startup reports a runtime start failure" do
    definition =
      Jido.Agent.new!(name: "failed_runtime_start", plugins: [{Runtime, start: :error}])

    assert {:ok, server} = Server.start_link(agent: definition)

    assert_receive {:EXIT, ^server,
                    {:shutdown,
                     {:bootstrap_failed, {:plugin_child_start_failed, Runtime, reason}}}},
                   1_000

    assert {:shutdown, {:failed_to_start_child, Runtime, :runtime_unavailable}} = reason
  end

  test "a structured owner shutdown stops the Plugin tree with normal shutdown" do
    definition = Jido.Agent.new!(name: "plugin_shutdown_reason", plugins: [Runtime])
    server = start_supervised!({Server, agent: definition})
    assert :ok = Server.await_ready(server)
    {:idle, state} = :sys.get_state(server)
    child = state.children[{:plugin, Runtime}]
    wrapper_ref = Process.monitor(child.lifecycle_pid)
    runtime_ref = Process.monitor(child.pid)

    assert :ok = Server.stop(server, {:shutdown, :requested})

    assert_receive {:DOWN, ^wrapper_ref, :process, wrapper, :shutdown}, 1_000
    assert wrapper == child.lifecycle_pid
    assert_receive {:DOWN, ^runtime_ref, :process, runtime, :shutdown}, 1_000
    assert runtime == child.pid
  end

  defp start_wrapper(extra \\ []) do
    {:ok, [spec]} = Jido.Plugin.normalize_all([Runtime])
    init = %Init{agent_server: self(), agent_id: unique_id("plugin-wrapper"), module: Runtime}
    child_spec = Runtime.child_spec(init)
    args = [self(), spec, child_spec] ++ extra
    wrapper = start_supervised!(Supervisor.child_spec({PluginChild, args}, restart: :temporary))
    {wrapper, PluginChild.child_pid(wrapper), init, spec}
  end

  defp request_restart(wrapper, runtime) do
    runtime_ref = Process.monitor(runtime)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :killed}, 1_000
    assert_receive {:plugin_runtime_restarting, ^wrapper, Runtime}, 1_000
    assert_receive {:plugin_runtime_bootstrap, ^wrapper, Runtime, token}, 1_000
    assert PluginChild.child_pid(wrapper) == :restarting
    token
  end
end
