defmodule Jido.AgentServer.Signal.CronTick do
  @moduledoc false

  use Jido.Signal,
    type: "jido.cron_tick",
    extension_policy: [
      {Jido.Signal.Ext.Trace, :optional},
      {Jido.Signal.Ext.Dispatch, :optional}
    ],
    schema: [
      job_id: [type: :any, required: true, doc: "The logical cron job id"],
      message: [type: :any, required: true, doc: "The cron tick message payload"]
    ]
end
