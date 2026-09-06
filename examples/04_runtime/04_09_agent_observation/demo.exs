# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

alias Jido.AgentServer, as: Server
alias Jido.Examples.TurnObservation, as: Agent
alias Jido.Examples.TurnObservation.EventProbe

{:ok, instance} = Jido.start_link(name: ObservationProbe)
probe = EventProbe.attach("observed")

try do
  {:ok, server} = Jido.start_agent(ObservationProbe, Agent, id: "observed")
  {:ok, _agent} = Agent.record(server, 7)
  {:ok, _agent} = Agent.send_to_missing_child(server, 11)
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
