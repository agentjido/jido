Code.require_file("checkpoint_identity_probe.ex", __DIR__)
Code.require_file("persistent_agent.ex", __DIR__)

defmodule Jido.Examples.Persistence.PersistentAgentTest do
  use Jido.Test.Agent.Case
  @moduletag :integration

  @moduletag group: :persistence
  @moduletag complexity: 3
  alias Jido.Examples.Persistence.PersistentAgent
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  test "a persistent Agent restores its last durable commit and continues", c do
    persistence = persistence(:restore)
    %{jido: jido} = restart_jido!(c, persistence)
    id = unique_id("persistent-counter")

    counter = start_counter(jido, id, persistence)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             PersistentAgent.increment(counter, "command-1", 2)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             PersistentAgent.increment(counter, "command-2", 3)

    committed = Jido.AgentServer.snapshot(counter).agent
    assert committed.state.count == 5
    assert agent_result(counter).agent_revision == 2

    stop_server(jido, counter)

    assert {:ok, restored} = PersistentAgent.restore(jido, id)
    assert :ok = Jido.AgentServer.await_ready(restored)

    assert %{
             state: %{
               count: 5,
               handled_signal_ids: ["command-1", "command-2"],
               last_command: %{signal_id: "command-2", amount: 3}
             },
             agent_revision: 2
           } = agent_result(restored)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             PersistentAgent.increment(restored, "command-3", 4)

    continued = Jido.AgentServer.snapshot(restored).agent
    assert continued.state.count == 9
    assert agent_result(restored).agent_revision == 3
  end

  test "an identical-state commit stores a new revision and restores it", c do
    persistence = persistence(:duplicate)
    %{jido: jido} = restart_jido!(c, persistence)
    id = unique_id("persistent-counter")
    duplicate = PersistentAgent.increment_signal!("command-1", 7)

    counter = start_counter(jido, id, persistence)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(counter, duplicate)

      assert turn_result.status in [:committed, :waiting]
      first = Jido.AgentServer.snapshot(counter).agent
    )

    assert first.state.count == 7
    stop_server(jido, counter)

    assert {:ok, restored} = PersistentAgent.restore(jido, id)

    assert :ok = Jido.AgentServer.await_ready(restored)
    snapshot = Jido.AgentServer.snapshot(restored)
    assert snapshot.agent == first
    assert snapshot.agent_revision == 1

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(restored, duplicate)

      assert turn_result.status in [:committed, :waiting]
      assert first == Jido.AgentServer.snapshot(restored).agent
    )

    snapshot = Jido.AgentServer.snapshot(restored)
    assert snapshot.agent == first
    assert snapshot.agent_revision == 2

    # Read before hibernation so a stop-time write cannot hide a missed commit.
    assert {:ok, ^first, stored_revision} =
             Persistence.load_agent_with_revision(persistence, PersistentAgent, id, instance: jido)

    assert stored_revision >= 3

    invalid = %{duplicate | id: "invalid-command", data: %{amount: "invalid"}}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _reason}} =
             Jido.AgentServer.call(restored, invalid)

    snapshot = Jido.AgentServer.snapshot(restored)
    assert snapshot.agent == first
    assert snapshot.agent_revision == 2

    assert {:ok, ^first, failed_revision} =
             Persistence.load_agent_with_revision(persistence, PersistentAgent, id, instance: jido)

    assert failed_revision > stored_revision

    stop_server(jido, restored)
    assert {:ok, restored_again} = PersistentAgent.restore(jido, id)
    assert :ok = Jido.AgentServer.await_ready(restored_again)
    snapshot = Jido.AgentServer.snapshot(restored_again)
    assert snapshot.agent == first
    assert snapshot.agent_revision == 2
  end

  test "a corrupt record prevents restore", c do
    {ETS, opts} = persistence = persistence(:corrupt)
    %{jido: jido} = restart_jido!(c, persistence)
    id = unique_id("corrupt-counter")

    key =
      Persistence.agent_key(Jido.Agent.Ref.new!(namespace: Jido.Instance.NamespaceRegistry.namespace(jido), id: id))

    assert :ok = ETS.put(key, <<0, 1, 2>>, opts)

    assert {:error, _reason} =
             with(
               {:ok, server} <- PersistentAgent.restore(jido, id),
               do: Jido.AgentServer.await_ready(server)
             )
  end

  defp start_counter(jido, id, _persistence) do
    start_agent!(jido, PersistentAgent,
      id: id,
      persistence_mode: :create
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
