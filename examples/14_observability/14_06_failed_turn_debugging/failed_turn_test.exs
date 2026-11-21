Code.require_file("../support/event_probe.ex", __DIR__)
Code.require_file("failed_turn.ex", __DIR__)

defmodule Jido.Examples.Observability.FailedTurnTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Observability.FailedTurn.Agent
  alias Jido.Examples.Runtime.EventProbe

  test "the result, status, and telemetry identify a failure before commit" do
    instance = :"failed_turn_example_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: instance}, id: instance)
    id = "failed-turn-#{System.unique_integer([:positive])}"
    probe = EventProbe.attach(id)

    try do
      {:ok, server} = Jido.start_agent(instance, Agent, id: id)
      assert :ok = AgentServer.await_ready(server)

      # The generated helper builds the Signal envelope. The Action schema is
      # an execution boundary, so the hosted Turn validates its input.
      assert {:ok, external} = Agent.set_signal(%{value: -1})

      assert {:ok,
              %AgentServer.TurnResult{
                status: :failed,
                agent_revision: 0,
                error: %Jido.Error.ValidationError{}
              }} = AgentServer.call(server, external)

      status = AgentServer.status(server)
      assert status.work_state == :idle
      assert status.agent_revision == 0
      assert status.last_outcome.status == :failed
      refute status.last_outcome.committed?
      assert AgentServer.snapshot(server).agent.state.value == 0

      settled =
        eventually(fn ->
          Enum.find(EventProbe.events(probe), fn event ->
            event.event == [:jido, :agent_server, :turn, :settled] and
              event.metadata.signal_id == external.id
          end)
        end)

      assert settled.metadata.status == :error
      refute settled.metadata.committed?
      assert settled.measurements.state_version_after == 0
      assert :ok = Jido.stop_agent(instance, server)
    after
      EventProbe.detach(probe)
    end
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    case fun.() do
      value when value in [nil, false] ->
        receive do
        after
          10 -> eventually(fun, attempts - 1)
        end

      value ->
        value
    end
  end
end
