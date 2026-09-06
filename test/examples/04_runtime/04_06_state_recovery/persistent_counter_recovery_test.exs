defmodule JidoTest.Examples.Runtime.PersistentCounterRecoveryTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime
  @moduletag complexity: 3

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PersistentCounterRecovery
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  test "a hibernated counter restores its last durable commit and continues", %{jido: jido} do
    persistence = persistence(:restore)
    id = unique_id("persistent-counter")

    counter = start_counter(jido, id, persistence)
    assert {:ok, _agent} = PersistentCounterRecovery.increment(counter, "command-1", 2)
    assert {:ok, committed} = PersistentCounterRecovery.increment(counter, "command-2", 3)
    assert committed.state.count == 5
    assert agent_result(counter).state_version == 2

    hibernate(counter)

    assert {:ok, restored} = PersistentCounterRecovery.restore(jido, id, persistence)

    assert %{
             state: %{
               count: 5,
               handled_signal_ids: ["command-1", "command-2"],
               last_command: %{signal_id: "command-2", amount: 3}
             },
             state_version: 2
           } = agent_result(restored)

    assert {:ok, continued} =
             PersistentCounterRecovery.increment(restored, "command-3", 4)

    assert continued.state.count == 9
    assert agent_result(restored).state_version == 3
  end

  test "an identical-state commit stores a new revision and restores it", %{jido: jido} do
    persistence = persistence(:duplicate)
    id = unique_id("persistent-counter")
    duplicate = PersistentCounterRecovery.increment_signal!("command-1", 7)

    counter = start_counter(jido, id, persistence)
    assert {:ok, first} = Server.call(counter, duplicate)
    assert first.state.count == 7
    hibernate(counter)

    assert {:ok, restored} =
             PersistentCounterRecovery.restore(jido, id, persistence,
               error_policy: fn _, _ -> :continue end
             )

    assert Server.snapshot(restored) == %{agent: first, state_version: 1}
    assert {:ok, ^first} = Server.call(restored, duplicate)
    assert Server.snapshot(restored) == %{agent: first, state_version: 2}

    # Read before hibernation so a stop-time write cannot hide a missed commit.
    assert {:ok, ^first, 2} =
             Persistence.load_agent_with_revision(persistence, PersistentCounterRecovery, id,
               instance: jido
             )

    invalid = %{duplicate | id: "invalid-command", data: %{amount: "invalid"}}
    assert {:error, _reason} = Server.call(restored, invalid)
    assert Server.snapshot(restored) == %{agent: first, state_version: 2}

    assert {:ok, ^first, 2} =
             Persistence.load_agent_with_revision(persistence, PersistentCounterRecovery, id,
               instance: jido
             )

    hibernate(restored)
    assert {:ok, restored_again} = PersistentCounterRecovery.restore(jido, id, persistence)
    assert Server.snapshot(restored_again) == %{agent: first, state_version: 2}
  end

  test "required restore reports a missing record", %{jido: jido} do
    assert {:error, _reason} =
             PersistentCounterRecovery.restore(
               jido,
               unique_id("missing-counter"),
               persistence(:missing)
             )
  end

  test "a corrupt record prevents restore", %{jido: jido} do
    {ETS, opts} = persistence = persistence(:corrupt)
    id = unique_id("corrupt-counter")
    key = Persistence.agent_key(jido, PersistentCounterRecovery, id)

    assert :ok = ETS.put(key, <<0, 1, 2>>, opts)

    assert {:error, _reason} =
             PersistentCounterRecovery.restore(jido, id, persistence)
  end

  test "a stale durable writer cannot replace a newer revision" do
    persistence = persistence(:conflict)
    id = unique_id("conflict-counter")

    older = PersistentCounterRecovery.new!(id: id, state: %{count: 1})
    newer = PersistentCounterRecovery.new!(id: id, state: %{count: 2})

    assert :ok = Persistence.save_agent(persistence, newer, revision: 2)
    assert {:error, :conflict} = Persistence.save_agent(persistence, older, revision: 1)

    assert {:ok, ^newer, 2} =
             Persistence.load_agent_with_revision(persistence, PersistentCounterRecovery, id)
  end

  defp start_counter(jido, id, persistence) do
    start_agent!(jido, PersistentCounterRecovery,
      id: id,
      persistence: persistence,
      restore: false
    )
  end

  defp hibernate(server) do
    monitor = Process.monitor(server)
    assert :ok = Server.hibernate(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :hibernate}}, 1_000
  end

  defp persistence(name) do
    table = :"example_persistent_counter_#{name}_#{System.unique_integer([:positive])}"
    {ETS, table: table}
  end
end
