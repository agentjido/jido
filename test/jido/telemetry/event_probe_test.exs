defmodule JidoTest.Telemetry.EventProbeTest do
  use ExUnit.Case, async: true

  alias Jido.Examples.Runtime.EventProbe

  test "the finite probe captures notification, Scheduler, and ownership events" do
    probe = EventProbe.attach_all()

    try do
      events = [
        [:jido, :agent, :after_commit, :stop],
        [:jido, :scheduler, :delivery],
        [:jido, :topology, :ownership, :settled]
      ]

      for event <- events do
        :telemetry.execute(event, %{count: 1}, %{status: :ok})
      end

      assert Enum.map(EventProbe.events(probe), & &1.event) == events

      :telemetry.execute([:jido, :agent_server, :signal, :stop], %{}, %{})
      assert Enum.map(EventProbe.events(probe), & &1.event) == events
    after
      EventProbe.detach(probe)
    end
  end
end
