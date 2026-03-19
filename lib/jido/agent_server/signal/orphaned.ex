defmodule Jido.AgentServer.Signal.Orphaned do
  @moduledoc """
  Emitted when a child survives logical parent death and becomes orphaned.

  Delivered to the child itself as `jido.agent.orphaned` after the runtime has
  already cleared the current parent reference. This lets child actions make
  decisions using the former-parent snapshot without accidentally treating the
  dead parent as still attached.

  ## Fields

  - `:parent_id` - ID of the former parent agent
  - `:parent_pid` - PID of the former parent process
  - `:tag` - Tag the former parent used for this child
  - `:meta` - Former parent metadata from the child's prior `ParentRef`
  - `:reason` - Exit reason from the former parent process
  """

  use Jido.Signal,
    type: "jido.agent.orphaned",
    schema: [
      parent_id: [type: :string, required: true, doc: "ID of the parent agent that died"],
      parent_pid: [type: :any, required: true, doc: "PID of the parent process that died"],
      tag: [type: :any, required: true, doc: "Tag assigned by the former parent"],
      meta: [type: :map, default: %{}, doc: "Metadata copied from the former parent reference"],
      reason: [type: :any, required: true, doc: "Exit reason from the parent process"]
    ]
end
