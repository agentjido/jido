Code.require_file("../support/event_probe.ex", __DIR__)
Code.require_file("turn_observation.ex", __DIR__)

defmodule Jido.Examples.Runtime.AgentObservationTest do
  use Jido.Test.Agent.Case
  @moduletag :integration

  @moduletag group: :runtime
  alias Jido.Examples.TurnObservation, as: Example
  alias Jido.Examples.Runtime.EventProbe

  test "semantic events distinguish a committed Turn from a failed Turn", %{
    jido: jido
  } do
    id = unique_id("example-observation")
    probe = EventProbe.attach(id)

    try do
      assert {:ok, server} =
               Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Example, id: id)

      {:ok, success} = Example.record_signal(%{value: 7})

      {:ok, delivery} =
        Example.send_to_missing_child_signal(%{value: 11})

      (
        assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
                 Jido.AgentServer.call(server, success)

        assert turn_result.status in [:committed, :waiting]
      )

      assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _reason}} =
               Jido.AgentServer.call(server, delivery)

      eventually(fn -> Jido.AgentServer.status(server).work_state == :idle end)

      settled =
        eventually(fn ->
          events =
            Enum.filter(
              EventProbe.events(probe),
              &(&1.event == [:jido, :agent_server, :turn, :settled])
            )

          if length(events) == 2 do
            events
          end
        end)

      assert [recorded] =
               Enum.filter(settled, &(&1.metadata.signal_id == success.id))

      assert recorded.metadata.status == :ok
      assert recorded.metadata.committed?
      assert recorded.measurements.state_version_after == 1

      assert [failed_delivery] =
               Enum.filter(settled, &(&1.metadata.signal_id == delivery.id))

      assert failed_delivery.metadata.status == :error
      refute failed_delivery.metadata.committed?
      assert failed_delivery.measurements.state_version_after == 1

      refute inspect(settled) =~ "private-agent-state"
    after
      EventProbe.detach(probe)
    end
  end
end
