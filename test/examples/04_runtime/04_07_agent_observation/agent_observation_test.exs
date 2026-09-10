defmodule JidoTest.Examples.Runtime.AgentObservationTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.TurnObservation, as: Example
  alias Jido.Examples.Runtime.EventProbe

  test "semantic events distinguish a successful Turn from a committed Directive failure", %{
    jido: jido
  } do
    id = unique_id("example-observation")
    probe = EventProbe.attach(id)

    try do
      assert {:ok, server} = Jido.start_agent(jido, Example, id: id)
      success = Example.record_signal!(7)
      delivery = Example.send_to_missing_child_signal!(11)

      assert {:ok, _} = Server.call(server, success)
      assert {:ok, _} = Server.call(server, delivery)
      eventually(fn -> Server.status(server).phase == :idle end)

      settled =
        eventually(fn ->
          events =
            Enum.filter(
              EventProbe.events(probe),
              &(&1.event == [:jido, :agent, :turn, :settled])
            )

          if length(events) == 2, do: events
        end)

      assert [recorded] =
               Enum.filter(settled, &(&1.metadata.source_signal_id == success.id))

      assert recorded.metadata.status == :ok
      assert recorded.metadata.committed?
      assert recorded.measurements.state_version_after == 1

      assert [failed_delivery] =
               Enum.filter(settled, &(&1.metadata.source_signal_id == delivery.id))

      assert failed_delivery.metadata.status == :error
      assert failed_delivery.metadata.stage == :directive
      assert failed_delivery.metadata.committed?
      assert failed_delivery.measurements.state_version_after == 2
      refute inspect(settled) =~ "private-agent-state"
    after
      EventProbe.detach(probe)
    end
  end
end
