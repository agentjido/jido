defmodule Jido.AgentServer.Signal.Scheduled do
  @moduledoc false

  use Jido.Signal,
    type: "jido.scheduled",
    extension_policy: [
      {Jido.Signal.Ext.Trace, :optional},
      {Jido.Signal.Ext.Dispatch, :optional}
    ],
    schema: [
      message: [type: :any, required: true, doc: "The scheduled message payload"]
    ]
end
