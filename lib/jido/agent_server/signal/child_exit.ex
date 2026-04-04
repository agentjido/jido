defmodule Jido.AgentServer.Signal.ChildExit do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.child.exit",
    extension_policy: [
      {Jido.Signal.Ext.Trace, :optional},
      {Jido.Signal.Ext.Dispatch, :optional}
    ],
    schema: [
      tag: [type: :any, required: true, doc: "Tag assigned to the child when spawned"],
      pid: [type: :any, required: true, doc: "PID of the child process that exited"],
      reason: [type: :any, required: true, doc: "Exit reason from the child process"]
    ]
end
