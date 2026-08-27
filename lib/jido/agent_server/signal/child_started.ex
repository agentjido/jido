defmodule Jido.AgentServer.Signal.ChildStarted do
  @moduledoc """
  Emitted by a child agent when it finishes initialization and becomes ready.

  Delivered to the parent as `jido.agent.child.started`. This allows the parent
  to know when a spawned child is ready to receive signals.

  ## Fields

  - `:parent_id` - ID of the parent agent
  - `:child_id` - ID of the child agent
  - `:child_partition` - Partition of the child agent
  - `:child_module` - Module of the child agent
  - `:tag` - Tag used when spawning the child
  - `:pid` - PID of the child process
  - `:meta` - Metadata passed during spawn
  """

  use Jido.Signal,
    type: "jido.agent.child.started",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        parent_id: Zoi.string(description: "ID of the parent agent"),
        child_id: Zoi.string(description: "ID of the child agent"),
        child_partition: Zoi.any(description: "Partition of the child agent") |> Zoi.optional(),
        child_module: Zoi.any(description: "Module of the child agent"),
        tag: Zoi.any(description: "Tag used when spawning"),
        pid: Zoi.any(description: "PID of the child process"),
        meta: Zoi.map(description: "Metadata passed during spawn") |> Zoi.default(%{})
      })
end
