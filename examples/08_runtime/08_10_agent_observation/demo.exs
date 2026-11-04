# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

Code.require_file("../support/event_probe.ex", __DIR__)
Code.require_file("turn_observation.ex", __DIR__)

defmodule ObservationDemo do
  def capture(_event, _measurements, %{agent_id: id, signal_id: signal_id}, {owner, id}),
    do: send(owner, {:effects_stopped, signal_id})

  def capture(_event, _measurements, _metadata, _config), do: :ok
end

alias Jido.AgentServer, as: Server
alias Jido.Examples.TurnObservation, as: Agent
alias Jido.Examples.Runtime.EventProbe

{:ok, instance} = Jido.start_link(name: ObservationProbe)
probe = EventProbe.attach("observed")
handler = {ObservationDemo, make_ref()}

:ok =
  :telemetry.attach(
    handler,
    [:jido, :agent_server, :effects, :stop],
    &ObservationDemo.capture/4,
    {self(), "observed"}
  )

try do
  {:ok, server} = Jido.start_agent(ObservationProbe, Agent, id: "observed")
  :ok = Server.await_ready(server)

  {:ok, route_signal_1} = Agent.record_signal(%{value: 7})

  {:ok, _agent, _directives} =
    Jido.AgentServer.call(server, route_signal_1, [])

  {:ok, route_signal_2} = Agent.send_to_missing_child_signal(%{value: 11})

  {:ok, _agent, _directives} =
    Jido.AgentServer.call(server, route_signal_2, [])

  # A call confirms the commit. Observe effect completion separately.
  delivery_id = route_signal_2.id

  receive do
    {:effects_stopped, ^delivery_id} -> :ok
  after
    5_000 -> raise "No effect completion event"
  end

  %{state_version: 2} = Server.status(server)
  :ok = Jido.stop_agent(ObservationProbe, server)

  outcomes =
    for %{event: [:jido, :agent_server, :turn, :settled]} = event <- EventProbe.events(probe) do
      %{
        outcome: Map.take(event.metadata, [:turn_id, :status, :stage, :committed?]),
        revision: event.measurements.state_version_after
      }
    end

  [
    %{outcome: %{status: :ok}, revision: 1},
    %{outcome: %{status: :ok, committed?: true}, revision: 2}
  ] = outcomes

  true =
    Enum.any?(EventProbe.events(probe), fn event ->
      event.event == [:jido, :agent_server, :effects, :stop] and
        event.metadata.status == :error
    end)

  IO.inspect(outcomes, label: "Committed Turns; delivery has a separate effects event")
  IO.inspect(Enum.map(Jido.Telemetry.metrics(), & &1.name), label: "Public metric names")
after
  :telemetry.detach(handler)
  EventProbe.detach(probe)
  Supervisor.stop(instance)
end
