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
    use Jido.Agent,
      name: "runtime_checkpoint_counter",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"checkpoint.increment", Increment}]
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
end
