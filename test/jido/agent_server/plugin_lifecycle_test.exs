defmodule Jido.AgentServer.PluginLifecycleTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.PluginLifecycle

  @moduletag capture_log: true

  defmodule Runtime do
    use GenServer
    use Jido.Plugin

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      case Keyword.get(init.options, :start_error) do
        nil -> {:ok, init}
        reason -> {:stop, reason}
      end
    end

    def await_ready(pid, opts) do
      result =
        case Keyword.get(opts, :gate) do
          nil -> :ok
          gate -> Elixir.Agent.get_and_update(gate, fn [result | rest] -> {result, rest} end)
        end

      case result do
        {:wait, observer} ->
          send(observer, {:readiness_waiting, self(), pid})

          receive do
            {:release_readiness, result} -> result
          end

        result ->
          result
      end
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "standalone_plugin_lifecycle"

    agent do
      schema Zoi.object(%{})
      plugin Runtime
    end
  end

  test "standalone Servers own a runtime tree and stop it on shutdown" do
    server = start_supervised!({Server, agent: Agent})
    assert :ok = Server.await_ready(server)
    {:idle, state} = :sys.get_state(server)
    child = state.children[{:plugin, Runtime}]
    assert {:ok, runtime} = PluginLifecycle.runtime_ref(state, Runtime)
    assert runtime == child.pid
    refs = for pid <- [child.pid, child.lifecycle_pid], do: {Process.monitor(pid), pid}
    send(child.lifecycle_pid, :unknown_message)
    assert :ok = PluginLifecycle.await_all(state)
    assert :ok = Server.stop(server)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _})
  end

  test "runtime lookup reports missing and stopped Plugin processes" do
    server = start_supervised!({Server, agent: Agent})
    assert :ok = Server.await_ready(server)
    {:idle, state} = :sys.get_state(server)
    child = state.children[{:plugin, Runtime}]
    direct = %{state | children: %{{:plugin, Runtime} => %{child | lifecycle_pid: nil}}}
    assert {:ok, pid} = PluginLifecycle.runtime_ref(direct, Runtime)
    assert pid == child.pid
    empty = %{state | children: %{}}
    assert {:error, {:plugin_runtime_not_found, Runtime}} = PluginLifecycle.await_all(empty)
    assert :ok = Server.stop(server)

    assert {:error, {:plugin_runtime_unavailable, Runtime, _}} =
             PluginLifecycle.runtime_ref(state, Runtime)
  end

  test "failed runtime startup returns a Plugin error", %{jido: jido} do
    definition = %{Agent.agent() | plugins: [{Runtime, start_error: :unavailable}]}

    assert {:error, {:bootstrap_failed, {:plugin_child_start_failed, Runtime, _}}} =
             Jido.start_agent(jido, definition, restart: :temporary)
  end

  test "failed readiness after a runtime restart stops the owner", %{jido: jido} do
    gate = start_supervised!({Elixir.Agent, fn -> [:ok, {:error, :not_ready}] end})
    definition = %{Agent.agent() | plugins: [{Runtime, gate: gate}]}
    {:ok, server} = Jido.start_agent(jido, definition, restart: :temporary)
    runtime = Server.children(server)[{:plugin, Runtime}].pid
    ref = Process.monitor(server)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^ref, :process, ^server, reason}, 2_000
    assert inspect(reason) =~ "plugin_runtime_readiness_failed"
    assert inspect(reason) =~ "not_ready"
    refute Process.alive?(runtime)
  end

  test "owner shutdown stops a pending restart readiness task and its runtime", %{jido: jido} do
    {server, wrapper, waiter, runtime} = paused_restart(jido)
    refs = for pid <- [server, wrapper, waiter, runtime], do: {Process.monitor(pid), pid}
    assert :ok = Jido.stop_agent(jido, server)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 2_000)
  end

  test "restart readiness task loss stops the owner and the unready runtime", %{jido: jido} do
    {server, wrapper, waiter, runtime} = paused_restart(jido)
    owner_ref = Process.monitor(server)
    wrapper_ref = Process.monitor(wrapper)
    runtime_ref = Process.monitor(runtime)
    Process.exit(waiter, :kill)

    assert_receive {:DOWN, ^owner_ref, :process, ^server, reason}, 2_000
    assert inspect(reason) =~ "plugin_runtime_readiness_failed"
    assert inspect(reason) =~ "killed"
    assert_receive {:DOWN, ^wrapper_ref, :process, ^wrapper, _}, 2_000
    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, _}, 2_000
  end

  defp paused_restart(jido) do
    observer = self()
    gate = start_supervised!({Elixir.Agent, fn -> [:ok, {:wait, observer}] end})
    definition = %{Agent.agent() | plugins: [{Runtime, gate: gate}]}
    {:ok, server} = Jido.start_agent(jido, definition, restart: :temporary)
    {:idle, state} = :sys.get_state(server)
    child = state.children[{:plugin, Runtime}]
    Process.exit(child.pid, :kill)
    assert_receive {:readiness_waiting, waiter, runtime}, 2_000
    assert Jido.AgentServer.PluginChild.child_pid(child.lifecycle_pid) == :restarting
    {server, child.lifecycle_pid, waiter, runtime}
  end
end
