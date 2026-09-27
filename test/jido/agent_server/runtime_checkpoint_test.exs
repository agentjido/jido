defmodule JidoTest.AgentServer.RuntimeCheckpointTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.RuntimeStore
  alias Jido.Signal

  defmodule Increment do
    use Jido.Action, name: "runtime_checkpoint_increment"

    def run(_params, context) do
      {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "runtime_checkpoint_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "checkpoint.increment", Increment
    end
  end

  defmodule StoreLocal do
    use Jido.Action, name: "runtime_checkpoint_local"
    def run(%{payload: payload}, _context), do: {:ok, %{payload: payload}}
  end

  defmodule LocalAgent do
    use Jido.Agent, name: "runtime_checkpoint_local_agent"

    agent do
      schema Zoi.object(%{payload: Zoi.any() |> Zoi.default(nil)})
    end

    routes do
      route "checkpoint.local", StoreLocal
    end
  end

  test "local restart copies values but does not recreate resources or transfer ownership", %{
    jido: jido
  } do
    observer = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        port = Port.open({:spawn_executable, System.find_executable("cat")}, [:binary])
        monitor = Process.monitor(observer)
        send(observer, {:resources, self(), port, monitor})

        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive {:resources, ^owner, port, reference}, 1_000
    port_monitor = :erlang.monitor(:port, port)
    id = unique_id("checkpoint-local")
    {:ok, server} = Jido.start_agent(jido, LocalAgent, id: id, restart: :temporary)

    payload = %{
      owner: owner,
      port: port,
      monitor: reference,
      observer: observer,
      bits: <<5::3>>,
      function: fn -> :local end,
      list: [1 | :tail]
    }

    assert {:ok, committed} = Server.call(server, signal("checkpoint.local", %{payload: payload}))
    assert committed.state.payload === payload

    recovered = restart_local(jido, server, id)
    assert Server.agent(recovered) == committed
    assert Server.snapshot(recovered).state_version == 1
    assert Process.alive?(owner)
    assert Port.info(port, :connected) == {:connected, owner}
    refute {:process, observer} in elem(Process.info(recovered, :monitors), 1)

    send(owner, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}, 1_000
    assert_receive {:DOWN, ^port_monitor, :port, ^port, _reason}, 1_000

    replacement = restart_local(jido, recovered, id)
    assert Server.agent(replacement) == committed
    refute Process.alive?(Server.agent(replacement).state.payload.owner)
    assert Port.info(Server.agent(replacement).state.payload.port) == nil
    assert Server.agent(replacement).state.payload.function.() == :local
    refute {:process, observer} in elem(Process.info(replacement, :monitors), 1)
  end

  test "clean stop and instance loss remove local runtime checkpoints", %{jido: jido} do
    id = unique_id("checkpoint-lifetime")
    {:ok, server} = Jido.start_agent(jido, LocalAgent, id: id, restart: :temporary)
    assert {:ok, _agent} = Server.call(server, signal("checkpoint.local", %{payload: <<5::3>>}))
    assert :ok = Server.stop(server)

    {:ok, clean} = Jido.start_agent(jido, LocalAgent, id: id, restart: :temporary)
    assert Server.agent(clean).state.payload == nil
    assert Server.snapshot(clean).state_version == 0
    assert {:ok, _agent} = Server.call(clean, signal("checkpoint.local", %{payload: self()}))

    monitor = Process.monitor(clean)
    Process.exit(clean, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^clean, :killed}, 1_000
    {:ok, supervisor} = ExUnit.fetch_test_supervisor()
    assert :ok = Supervisor.terminate_child(supervisor, jido)
    assert {:ok, _instance} = Supervisor.restart_child(supervisor, jido)

    {:ok, fresh} = Jido.start_agent(jido, LocalAgent, id: id, restart: :temporary)
    assert Server.agent(fresh).state.payload == nil
    assert Server.snapshot(fresh).state_version == 0
  end

  test "a committed Agent cannot restart from initial state while its store is unavailable", %{
    jido: jido
  } do
    id = unique_id("checkpoint-outage")
    {:ok, server} = Jido.start_agent(jido, Counter, id: id, restart: :temporary)

    assert {:ok, %{state: %{count: 1}}} =
             Server.call(server, Signal.new!("checkpoint.increment", %{}, source: "/test"))

    assert :ok = Supervisor.terminate_child(jido, Jido.runtime_store_name(jido))

    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 1_000

    assert {:error, :runtime_checkpoint_unavailable} =
             Jido.start_agent(jido, Counter, id: id, restart: :temporary)

    assert Jido.whereis_agent(jido, id) == nil

    assert {:ok, _store} = Supervisor.restart_child(jido, Jido.runtime_store_name(jido))
    assert {:ok, recovered} = Jido.start_agent(jido, Counter, id: id, restart: :temporary)
    assert Server.agent(recovered).state == %{count: 1}
    assert Server.snapshot(recovered).state_version == 1
  end

  test "a malformed runtime checkpoint cannot become initial state", %{jido: jido} do
    id = unique_id("checkpoint-invalid")
    {:ok, server} = Jido.start_agent(jido, Counter, id: id, restart: :temporary)

    assert :ok =
             RuntimeStore.put(
               jido,
               :agent_runtime_checkpoints,
               Jido.partition_key(id, nil),
               %{agent: :invalid, state_version: 1}
             )

    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 1_000

    assert {:error, :invalid_runtime_checkpoint} =
             Jido.start_agent(jido, Counter, id: id, restart: :temporary)
  end

  test "a checkpoint without an upgrade marker still restores its original definition", %{
    jido: jido
  } do
    id = unique_id("legacy-checkpoint")
    {:ok, server} = Jido.start_agent(jido, Counter, id: id, restart: :temporary)
    agent = %{Server.agent(server) | state: %{count: 9}}

    assert :ok =
             RuntimeStore.put(
               jido,
               :agent_runtime_checkpoints,
               Jido.partition_key(id, nil),
               %{agent: agent, state_version: 3}
             )

    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 1_000

    assert {:ok, recovered} = Jido.start_agent(jido, Counter, id: id, restart: :temporary)
    assert Server.agent(recovered).state == %{count: 9}
    assert Server.snapshot(recovered).state_version == 3
  end

  test "restored state is validated even when the startup definition is unchanged", %{jido: jido} do
    id = unique_id("checkpoint-invalid-state")
    {:ok, agent} = Counter.new(id: id)

    assert :ok =
             RuntimeStore.put(jido, :agent_runtime_checkpoints, Jido.partition_key(id, nil), %{
               agent: %{agent | state: %{count: "invalid"}},
               state_version: 1
             })

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.start_agent(jido, agent, restart: :temporary)

    assert Jido.whereis_agent(jido, id) == nil
  end

  defp restart_local(jido, server, id) do
    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 1_000
    assert {:ok, recovered} = Jido.start_agent(jido, LocalAgent, id: id, restart: :temporary)
    recovered
  end
end
