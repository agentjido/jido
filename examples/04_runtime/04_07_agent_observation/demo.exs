# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

alias Jido.AgentServer, as: Server
alias Jido.Examples.TurnObservation, as: Agent
alias Jido.Examples.Runtime.EventProbe

{:ok, instance} = Jido.start_link(name: ObservationProbe)
probe = EventProbe.attach("observed")

try do
  {:ok, server} = Jido.start_agent(ObservationProbe, Agent, id: "observed")

  {:ok, route_signal_1} = Agent.record_signal(%{value: 7})

  {:ok, _agent} =
    Jido.AgentServer.call(server, route_signal_1, [])

  {:ok, route_signal_2} = Agent.send_to_missing_child_signal(%{value: 11})

  {:ok, _agent} =
    Jido.AgentServer.call(server, route_signal_2, [])

  %{phase: :idle, state_version: 2} = Server.status(server)
  :ok = Jido.stop_agent(ObservationProbe, server)

  outcomes =
    for %{event: [:jido, :agent, :turn, :settled]} = event <- EventProbe.events(probe) do
      %{
        outcome: Map.take(event.metadata, [:turn_id, :status, :stage, :committed?]),
        revision: event.measurements.state_version_after
      }
    end

  [
    %{outcome: %{status: :ok}, revision: 1},
    %{outcome: %{status: :error, committed?: true}, revision: 2}
  ] = outcomes

  IO.inspect(outcomes, label: "SDK terminal events")
after
  EventProbe.detach(probe)
  Supervisor.stop(instance)
end
