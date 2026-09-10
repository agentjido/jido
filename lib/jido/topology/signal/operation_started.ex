defmodule Jido.Topology.Signal.OperationStarted do
  @moduledoc "A Topology Controller started an activation, repair, update, placement, or cleanup operation."

  use Jido.Signal,
    type: "jido.topology.lifecycle.operation.started",
    default_source: "/jido/topology",
    schema:
      Zoi.object(%{
        topology_id: Zoi.string(),
        operation_id: Zoi.string(),
        operation: Zoi.enum(~w(activate repair update place cleanup))
      })
end
