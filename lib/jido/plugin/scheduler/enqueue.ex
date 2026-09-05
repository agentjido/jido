defmodule Jido.Plugin.Scheduler.Enqueue do
  @moduledoc """
  Records a due occurrence through an ordinary Agent Turn.

  Route `jido.scheduler.enqueue` to this Action when using durable recurring
  delivery. It emits a Queue Directive; business work runs in a later Turn.
  """
  use Jido.Action,
    name: "scheduler_enqueue",
    schema:
      Zoi.object(%{
        job_id: Zoi.any(),
        generation: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2_147_483_647),
        scheduled_at:
          Zoi.string() |> Zoi.refine({Jido.Plugin.Scheduler.Occurrence, :validate_utc, []})
      })

  @impl true
  def run(input, context) do
    directive = %Jido.Plugin.Scheduler.Queue{
      job_id: input.job_id,
      generation: input.generation,
      scheduled_at: input.scheduled_at,
      scope: {Map.get(context, :jido), context.agent_id, Map.get(context, :partition)}
    }

    {:ok, context.agent_state, [directive]}
  end
end
