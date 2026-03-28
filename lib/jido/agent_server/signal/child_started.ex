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
    schema: [
      parent_id: [type: :string, required: true, doc: "ID of the parent agent"],
      child_id: [type: :string, required: true, doc: "ID of the child agent"],
      child_partition: [type: :any, doc: "Partition of the child agent"],
      child_module: [type: :any, required: true, doc: "Module of the child agent"],
      tag: [type: :any, required: true, doc: "Tag used when spawning"],
      pid: [type: :any, required: true, doc: "PID of the child process"],
      meta: [type: :map, default: %{}, doc: "Metadata passed during spawn"]
    ]
end
