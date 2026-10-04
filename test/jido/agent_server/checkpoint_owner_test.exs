defmodule Jido.AgentServer.CheckpointOwnerTest do
  use JidoTest.Case, async: true
  alias Jido.AgentServer.{Options, RuntimeCheckpoint, State, Storage}
  alias JidoTest.AgentFixtures.CounterAgent

  test "clean descendant shutdown retains a checkpoint only after its runtime owner dies", c do
    agent = CounterAgent.new!(id: unique_id("owned-checkpoint"))
    {owner, monitor} = spawn_monitor(fn -> receive do: (:stop -> :ok) end)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    for {checkpoint_owner, expected} <- [{owner, :retained}, {self(), :deleted}, {nil, :deleted}] do
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
end
