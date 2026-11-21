Code.require_file("commit_before_effects.ex", __DIR__)

defmodule Jido.Examples.AgentServer.CommitBeforeEffectsTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.AgentServer.CommitBeforeEffects.Counter

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"commit_before_effects_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)

    handler = {__MODULE__, make_ref()}
    event = [:jido, :agent_server, :effects, :stop]

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn event, measurements, metadata, owner ->
          send(owner, {:effect_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    %{instance: instance}
  end

  test "an effect failure does not roll back committed state", %{instance: instance} do
    assert {:ok, server} = Jido.start_agent(instance, Counter, id: "commit-counter")
    assert :ok = AgentServer.await_ready(server)
    {:ok, signal} = Counter.increment_signal(%{delivery_id: "delivery-1"})

    assert {:ok, %AgentServer.TurnResult{status: :committed, agent_revision: 1}} =
             AgentServer.call(server, signal, context: %{observer: self()})

    committed = AgentServer.snapshot(server)
    assert committed.agent.state == %{count: 1}
    assert committed.agent_revision == 1

    assert_receive {:delivery_attempted, "delivery-1", effect_snapshot}, 1_000
    assert effect_snapshot.agent == committed.agent
    assert effect_snapshot.agent_revision == 1

    assert_receive {:effect_event, [:jido, :agent_server, :effects, :stop], measurements,
                    %{status: :error, stage: :directive}},
                   1_000

    assert measurements.directive_completed == 0
    assert measurements.directive_count == 1
    assert AgentServer.snapshot(server) == committed
  end
end
