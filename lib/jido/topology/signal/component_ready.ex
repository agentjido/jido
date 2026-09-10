defmodule Jido.Topology.Signal.ComponentReady do
  @moduledoc "A planned Topology component is ready."

  use Jido.Signal,
    type: "jido.topology.lifecycle.component.ready",
    default_source: "/jido/topology",
    schema:
      Zoi.object(%{
        topology_id: Zoi.string(),
        operation_id: Zoi.string(),
        component: Zoi.string(),
        kind: Zoi.string(),
        node: Zoi.string()
      })
end
