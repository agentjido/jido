defmodule JidoTest.Examples.Persistence.PersistentAgentTest do
  use JidoTest.AgentCase

  @moduletag group: :persistence
  @moduletag complexity: 3

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Persistence.PersistentAgent
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  test "a persistent Agent restores its last durable commit and continues", %{jido: jido} do
    persistence = persistence(:restore)
    id = unique_id("persistent-counter")

    counter = start_counter(jido, id, persistence)
    assert {:ok, _agent} = PersistentAgent.increment(counter, "command-1", 2)
    assert {:ok, committed} = PersistentAgent.increment(counter, "command-2", 3)
    assert committed.state.count == 5
    assert agent_result(counter).state_version == 2

    stop_server(jido, counter)

    assert {:ok, restored} = PersistentAgent.restore(jido, id, persistence)

    assert %{
             state: %{
               count: 5,
               handled_signal_ids: ["command-1", "command-2"],
               last_command: %{signal_id: "command-2", amount: 3}
             },
             state_version: 2
           } = agent_result(restored)

    assert {:ok, continued} =
             PersistentAgent.increment(restored, "command-3", 4)

    assert continued.state.count == 9
    assert agent_result(restored).state_version == 3
  end

  test "an identical-state commit stores a new revision and restores it", %{jido: jido} do
    persistence = persistence(:duplicate)
    id = unique_id("persistent-counter")
    duplicate = PersistentAgent.increment_signal!("command-1", 7)

    counter = start_counter(jido, id, persistence)
    assert {:ok, first} = Server.call(counter, duplicate)
    assert first.state.count == 7
    stop_server(jido, counter)

    assert {:ok, restored} =
             PersistentAgent.restore(jido, id, persistence,
               error_policy: fn _, _ -> :continue end
             )

    assert Server.snapshot(restored) == %{agent: first, state_version: 1}
    assert {:ok, ^first} = Server.call(restored, duplicate)
    assert Server.snapshot(restored) == %{agent: first, state_version: 2}

    # Read before hibernation so a stop-time write cannot hide a missed commit.
    assert {:ok, ^first, 2} =
             Persistence.load_agent_with_revision(persistence, PersistentAgent, id,
               instance: jido
             )

    invalid = %{duplicate | id: "invalid-command", data: %{amount: "invalid"}}
    assert {:error, _reason} = Server.call(restored, invalid)
    assert Server.snapshot(restored) == %{agent: first, state_version: 2}

    assert {:ok, ^first, 2} =
             Persistence.load_agent_with_revision(persistence, PersistentAgent, id,
               instance: jido
             )

    stop_server(jido, restored)
    assert {:ok, restored_again} = PersistentAgent.restore(jido, id, persistence)
    assert Server.snapshot(restored_again) == %{agent: first, state_version: 2}
  end

  test "a corrupt record prevents restore", %{jido: jido} do
    {ETS, opts} = persistence = persistence(:corrupt)
    id = unique_id("corrupt-counter")
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: Jido.namespace(jido), id: id))

    assert :ok = ETS.put(key, <<0, 1, 2>>, opts)

    assert {:error, _reason} =
             PersistentAgent.restore(jido, id, persistence)
  end

  defp start_counter(jido, id, persistence) do
    start_agent!(jido, PersistentAgent,
      id: id,
      persistence: persistence,
      restore: false
    )
  end

  defp stop_server(jido, server) do
    monitor = Process.monitor(server)
    assert :ok = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 1_000
  end

  defp persistence(name) do
    table = :"example_persistent_counter_#{name}_#{System.unique_integer([:positive])}"
    {ETS, table: table}
  end
end
