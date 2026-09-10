defmodule Jido.Topology.Signal.StatusChanged do
  @moduledoc "A Topology Controller changed its readiness status."

  use Jido.Signal,
    type: "jido.topology.lifecycle.status.changed",
    default_source: "/jido/topology",
    schema:
      Zoi.object(%{
        topology_id: Zoi.string(),
        operation_id: Zoi.string(),
        previous: Zoi.enum(~w(ready degraded)) |> Zoi.nullable(),
        current: Zoi.enum(~w(ready degraded))
      })
end
