defmodule Jido.AgentServer.Signal.CronTick do
  @moduledoc false

  use Jido.Signal,
    type: "jido.cron_tick",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        job_id: Zoi.any(description: "The logical cron job id"),
        message: Zoi.any(description: "The cron tick message payload")
      })
end
