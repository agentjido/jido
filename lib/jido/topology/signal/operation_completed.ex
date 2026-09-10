defmodule Jido.Topology.Signal.OperationCompleted do
  @moduledoc "A Topology Controller completed one lifecycle operation."

  use Jido.Signal,
    type: "jido.topology.lifecycle.operation.completed",
    default_source: "/jido/topology",
    schema:
      Zoi.object(%{
        topology_id: Zoi.string(),
        operation_id: Zoi.string(),
        operation: Zoi.enum(~w(activate repair update place cleanup)),
        status: Zoi.enum(~w(ok error ready degraded))
      })
end
