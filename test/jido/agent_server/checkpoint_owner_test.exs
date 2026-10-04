defmodule Jido.AgentServer.CheckpointOwnerTest do
  use JidoTest.Case, async: true
  alias Jido.AgentServer.{Options, RuntimeCheckpoint, State, Storage}
  alias JidoTest.AgentFixtures.CounterAgent

  test "the owner retains checkpoints across clean descendant shutdown", c do
    agent = CounterAgent.new!(id: unique_id("owned-checkpoint"))
    {owner, monitor} = spawn_monitor(fn -> receive do: (:stop -> :ok) end)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    for {checkpoint_owner, expected} <- [{owner, :retained}, {self(), :retained}, {nil, :deleted}] do
      state =
        %State{
          jido: c.jido,
          agent: agent,
          config: %{checkpoint_owner: checkpoint_owner},
          postponed_tokens: MapSet.new(),
          state_version: 0,
          plugin_specs: [],
          active: nil
        }

      assert :ok = RuntimeCheckpoint.put(state, %{agent | state: %{agent.state | count: 4}}, 1)
      assert :ok = Storage.delete_runtime_checkpoint(:shutdown, state)
      {:ok, options} = Options.new(agent: CounterAgent, id: agent.id, jido: c.jido)
      assert {:ok, restored, version} = RuntimeCheckpoint.restore(options)

      assert {restored.state.count, version} ==
               if(expected == :retained, do: {4, 1}, else: {0, 0})
    end

    assert {:error, %Jido.Error.ValidationError{}} =
             Options.new(agent: CounterAgent, checkpoint_owner: :invalid)
  end

  for operation <- [:delete_local_owned, :delete_owned] do
    test "#{operation} reports an unavailable scan and keeps the checkpoint", c do
      id = unique_id("scan_failure")
      owner_key = {:topology, id, :runtime_owner}
      {:ok, _} = Registry.register(Jido.registry_name(c.jido), owner_key, nil)
      agent = CounterAgent.new!(id: id <> "/agent/counter")

      state = %State{
        jido: c.jido,
        agent: agent,
        config: %{checkpoint_owner: self()},
        postponed_tokens: MapSet.new(),
        state_version: 0,
        plugin_specs: [],
        active: nil
      }

      committed = %{agent | state: %{agent.state | count: 7}}
      assert :ok = RuntimeCheckpoint.put(state, committed, 1)

      # The ETS table belongs to the Jido supervisor and survives a store
      # worker outage. Keep that table while removing only worker lookup.
      name = Jido.runtime_store_name(c.jido)
      store = Process.whereis(name)
      assert Process.unregister(name)

      result =
        try do
          case unquote(operation) do
            :delete_local_owned ->
              RuntimeCheckpoint.delete_local_owned(c.jido, node(), [owner_key])

            :delete_owned ->
              RuntimeCheckpoint.delete_owned(c.jido, [owner_key])
          end
        after
          Process.register(store, name)
        end

      {:ok, options} = Options.new(agent: CounterAgent, id: agent.id, jido: c.jido)
      assert {:ok, ^committed, 1} = RuntimeCheckpoint.restore(options)
      assert {:error, :not_running} = result
    end
  end
end
