defmodule Jido.Topology.Signal.ComponentFailed do
  @moduledoc "A planned Topology component failed to become ready."

  use Jido.Signal,
    type: "jido.topology.lifecycle.component.failed",
    default_source: "/jido/topology",
    schema:
      Zoi.object(%{
        topology_id: Zoi.string(),
        operation_id: Zoi.string(),
        component: Zoi.string(),
        kind: Zoi.string(),
        node: Zoi.string(),
        reason: Zoi.string()
      })
end
