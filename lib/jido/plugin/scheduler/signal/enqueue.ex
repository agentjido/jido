defmodule Jido.Plugin.Scheduler.Signal.Enqueue do
  @moduledoc "Requests an Agent Turn to record one due schedule occurrence."

  use Jido.Signal,
    type: "jido.scheduler.enqueue",
    default_source: "/jido/scheduler",
    schema:
      Zoi.object(%{
        job_id: Zoi.any(),
        generation: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2_147_483_647),
        scheduled_at:
          Zoi.string() |> Zoi.refine({Jido.Plugin.Scheduler.Occurrence, :validate_utc, []})
      })
end
