# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

alias Jido.Examples.Topology.Cell
alias Jido.Examples.TurnObservation, as: Agent
alias Jido.Examples.Runtime.EventProbe
alias Jido.Topology.{Builder, Controller}

instance = SemanticBoundaryProbe
namespace = "examples/semantic-boundary"
persistence = {Jido.Persistence.ETS, table: SemanticBoundaryProbe}
table = :ets.new(SemanticBoundaryProbe_records, [:named_table, :public, :set])

{:ok, supervisor} =
  Jido.start_link(name: instance, namespace: namespace, persistence: persistence)

probe = EventProbe.attach_all()

try do
  {:ok, server} = Jido.start_agent(instance, Agent, id: "observed", partition: "west")
  {:ok, _agent} = Agent.record(server, 7)
  :ok = Jido.hibernate(instance, server, partition: "west")
  {:ok, thawed} = Jido.thaw(instance, Agent, "observed", partition: "west")
  :ok = Jido.stop_agent(instance, thawed)

  topology =
    Builder.new(name: "observed-topology")
    |> Builder.agent(:cell, Cell)
    |> Builder.build!(id: "observed-topology")

  {:ok, controller} = Controller.start_link(jido: instance, topology: topology, repair: :manual)
  :ok = Controller.await_ready(controller)
  :ok = Controller.reconcile(controller)
  :ok = Controller.await_ready(controller)
  :ok = Supervisor.stop(controller)

  events = EventProbe.events(probe)

  facts =
    for event <- events,
        Enum.take(event.event, 2) != [:jido, :agent_server],
        List.last(event.event) in [:stop, :settled, :rejected],
        do: %{
          event: event.event,
          operation: event.metadata[:operation] || event.metadata[:topology_operation],
          status: event.metadata[:status],
          schema_version: event.metadata.schema_version
        }

  true = Enum.any?(facts, &(&1.event == [:jido, :agent, :turn, :settled]))
  true = Enum.any?(facts, &(&1.event == [:jido, :persistence, :operation, :stop]))
  true = Enum.any?(facts, &(&1.event == [:jido, :topology, :operation, :stop]))

  IO.inspect(facts, label: "Semantic runtime facts")
after
  EventProbe.detach(probe)
  Supervisor.stop(supervisor)
  :ets.delete(table)
end
