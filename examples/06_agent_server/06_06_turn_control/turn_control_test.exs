Code.require_file("turn_control.ex", __DIR__)

defmodule Jido.Test.Examples.Runtime.TurnControlBlockingAction do
  @moduledoc false
  use Jido.Action,
    name: "test_runtime_turn_control_blocking_action",
    schema: Jido.Joi.object(%{name: Jido.Joi.string() |> Jido.Joi.min(1)})

  alias Jido.Test.AgentServer.RuntimeBarrier

  def run(%{name: name}, context) do
    :ok = RuntimeBarrier.wait()
    {:ok, %{context.agent_state | completed: context.agent_state.completed ++ [name]}}
  end
end

defmodule Jido.Test.Examples.Runtime.TurnControlBlockingAgent do
  @moduledoc false
  use Jido.Agent, name: "test_runtime_turn_control_blocking_agent"

  state do
    schema Jido.Joi.object(%{completed: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/test/examples/runtime/turn_control"

    route "test.examples.runtime.turn_control.complete",
          Jido.Test.Examples.Runtime.TurnControlBlockingAction do
    end
  end
end

defmodule Jido.Examples.Runtime.TurnControlTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  alias Jido.Test.Examples.Runtime.TurnControlBlockingAgent
  alias Jido.Test.AgentServer.RuntimeBarrier

  setup do
    start_supervised!(RuntimeBarrier)
    :ok
  end

  test "public status identifies and cancels only the matching active Turn", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, TurnControlBlockingAgent, id: unique_id("turn-control"))

    :ok = RuntimeBarrier.arm(self())

    caller =
      Task.async(fn ->
        signal =
          Jido.Signal.new!(
            "test.examples.runtime.turn_control.complete",
            %{name: "cancelled"},
            source: "/test/examples/runtime/turn_control"
          )

        Jido.AgentServer.call(server, signal)
      end)

    assert_receive :runtime_barrier_waiting, 1_000

    assert %Jido.AgentServer.Status{
             work_state: :running,
             agent_revision: 0,
             active_turn_id: turn_id
           } = Jido.AgentServer.status(server)

    assert {:error, :stale_turn} = Jido.AgentServer.cancel_turn(server, "stale-turn-id")
    assert :ok = Jido.AgentServer.cancel_turn(server, turn_id)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :cancelled}} = Task.await(caller)

    assert %{agent_revision: 0, agent: %{state: %{completed: []}}} =
             Jido.AgentServer.snapshot(server)

    assert %{work_state: :idle, active_turn_id: nil} = Jido.AgentServer.status(server)
  end

  defp blocked(jido) do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, TurnControlBlockingAgent, id: unique_id())

    :ok = RuntimeBarrier.arm(self())
    pending = Jido.AgentServer.submit(server, complete("active"))
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
    queued = Jido.AgentServer.submit(server, complete("queued"))
    assert Jido.AgentServer.status(server).queue_depth == 1
    control = Task.async(fn -> Jido.AgentServer.quiesce(server) end)
    eventually(fn -> Jido.AgentServer.status(server).admission != :open end)
    assert {:error, :quiesced} = Jido.AgentServer.await(queued)

    assert {:error, :quiesced} = Jido.AgentServer.call(server, complete("closed"))

    assert Jido.AgentServer.snapshot(server).agent.state.completed == []
    assert Jido.AgentServer.snapshot(server).agent_revision == 0
    assert :ok = RuntimeBarrier.release()

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.AgentServer.await(active)

    assert {:ok, %Jido.AgentServer.Status{admission: :quiesced}} = Task.await(control)
    assert Jido.AgentServer.status(server).admission == :quiesced
    assert {:ok, %Jido.AgentServer.Status{admission: :open}} = Jido.AgentServer.resume(server)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, complete("resumed"))

      assert turn_result.status in [:committed, :waiting]
      %{state: %{completed: ["active", "resumed"]}} = Jido.AgentServer.snapshot(server).agent
    )
  end

  test "quiesce can cancel active work before commit", %{jido: jido} do
    {server, pending} = blocked(jido)

    assert {:ok, %Jido.AgentServer.Status{admission: :quiesced}} =
             Jido.AgentServer.quiesce(server, active: :cancel)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :cancelled}} =
             Jido.AgentServer.await(pending)

    assert Jido.AgentServer.snapshot(server).agent.state.completed == []
    assert Jido.AgentServer.status(server).admission == :quiesced
    assert {:ok, %Jido.AgentServer.Status{admission: :open}} = Jido.AgentServer.resume(server)
  end
end
