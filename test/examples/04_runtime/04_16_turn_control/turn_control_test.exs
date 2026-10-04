defmodule JidoTest.Examples.Runtime.TurnControlBlockingAction do
  @moduledoc false
  use Jido.Action,
    name: "test_runtime_turn_control_blocking_action",
    schema: Zoi.object(%{name: Zoi.string() |> Zoi.min(1)})

  alias JidoTest.Examples.RuntimeBarrier

  def run(%{name: name}, context) do
    :ok = RuntimeBarrier.wait()
    {:ok, %{context.agent_state | completed: context.agent_state.completed ++ [name]}}
  end
end

defmodule JidoTest.Examples.Runtime.TurnControlBlockingAgent do
  @moduledoc false
  use Jido.Agent, name: "test_runtime_turn_control_blocking_agent"

  agent do
    schema Zoi.object(%{completed: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/test/examples/runtime/turn_control"

    route "test.examples.runtime.turn_control.complete",
          JidoTest.Examples.Runtime.TurnControlBlockingAction
  end
end

defmodule JidoTest.Examples.Runtime.TurnControlTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer
  alias JidoTest.Examples.Runtime.TurnControlBlockingAgent
  alias JidoTest.Examples.RuntimeBarrier

  setup do
    start_supervised!(RuntimeBarrier)
    :ok
  end

  test "public status identifies and cancels only the matching active Turn", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, TurnControlBlockingAgent, id: unique_id("turn-control"))

    :ok = RuntimeBarrier.arm(self())

    caller =
      Task.async(fn ->
        signal =
          Jido.Signal.new!(
            "test.examples.runtime.turn_control.complete",
            %{name: "cancelled"},
            source: "/test/examples/runtime/turn_control"
          )

        AgentServer.call(server, signal)
      end)

    assert_receive :runtime_barrier_waiting, 1_000

    assert %{
             phase: phase,
             state_version: 0,
             active: %{turn_id: turn_id, signal_type: signal_type, start_version: 0}
           } = AgentServer.status(server)

    assert phase == :running
    assert signal_type == "test.examples.runtime.turn_control.complete"
    assert {:error, :stale_turn} = AgentServer.cancel_turn(server, "stale-turn-id")
    assert :ok = AgentServer.cancel_turn(server, turn_id)
    assert {:error, :cancelled} = Task.await(caller)
    assert %{state_version: 0, agent: %{state: %{completed: []}}} = AgentServer.snapshot(server)
    assert %{phase: :idle, active: nil} = AgentServer.status(server)
  end
end
