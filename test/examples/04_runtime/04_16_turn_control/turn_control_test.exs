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

  state do
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
      JidoTest.ExampleRuntime.start_agent(jido, TurnControlBlockingAgent,
        id: unique_id("turn-control")
      )

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
             active: %{turn_id: turn_id, signal_id: signal_id, start_version: 0}
           } = AgentServer.status(server)

    assert phase == :running
    assert is_binary(signal_id)
    assert {:error, :stale_turn} = AgentServer.cancel_turn(server, "stale-turn-id")
    assert :ok = AgentServer.cancel_turn(server, turn_id)
    assert {:error, :cancelled} = Task.await(caller)
    assert %{state_version: 0, agent: %{state: %{completed: []}}} = AgentServer.snapshot(server)
    assert %{phase: :idle, active: nil} = AgentServer.status(server)
  end

  defp blocked(jido) do
    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(jido, TurnControlBlockingAgent, id: unique_id())

    :ok = RuntimeBarrier.arm(self())
    pending = AgentServer.submit(server, complete("active"))
    assert_receive :runtime_barrier_waiting, 1_000
    {server, pending}
  end

  defp complete(name),
    do:
      Jido.Signal.new!(
        "test.examples.runtime.turn_control.complete",
        %{name: name},
        source: "/test/examples/runtime/turn_control"
      )

  test "quiesce closes admission, drains active work, and resume accepts new work", %{jido: jido} do
    {server, active} = blocked(jido)
    queued = AgentServer.submit(server, complete("queued"))
    assert AgentServer.status(server).admission.postponed == 1
    control = Task.async(fn -> AgentServer.quiesce(server) end)
    eventually(fn -> AgentServer.status(server).admission.mode != :open end)
    assert {:error, :quiesced} = AgentServer.await(queued)
    assert {:error, :quiesced} = AgentServer.call(server, complete("closed"))
    assert AgentServer.agent(server).state.completed == []
    assert AgentServer.snapshot(server).state_version == 0
    assert :ok = RuntimeBarrier.release()
    assert {:ok, _, []} = AgentServer.await(active)
    assert :ok = Task.await(control)
    assert AgentServer.status(server).admission.mode == :quiesced
    assert :ok = AgentServer.resume(server)

    assert {:ok, %{state: %{completed: ["active", "resumed"]}}, []} =
             AgentServer.call(server, complete("resumed"))
  end

  test "quiesce can cancel active work before commit", %{jido: jido} do
    {server, pending} = blocked(jido)
    assert :ok = AgentServer.quiesce(server, active: :cancel)
    assert {:error, :cancelled} = AgentServer.await(pending)
    assert AgentServer.agent(server).state.completed == []
    assert AgentServer.status(server).admission.mode == :quiesced
    assert :ok = AgentServer.resume(server)
  end
end
