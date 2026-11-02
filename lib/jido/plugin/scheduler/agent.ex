defmodule Jido.Plugin.Scheduler.Agent do
  alias Jido.Joi
  @moduledoc false
  @behaviour Jido.Plugin

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Cancel, Cron, Schedule}
  alias Jido.Signal

  @cron_spec_schema Joi.object(
                      %{
                        cron_expression: Joi.string(),
                        message: Joi.struct(Signal),
                        timezone: Joi.string(),
                        generation: Joi.integer() |> Joi.min(0) |> Joi.max(2_147_483_647) |> Joi.optional()
                      },
                      unrecognized_keys: :error
                    )
  @state_schema Joi.object(%{
                  cron:
                    Joi.map(Joi.any(), @cron_spec_schema, description: "Recurring schedule definitions")
                    |> Joi.refine({Scheduler, :validate_cron_state, []})
                })
                |> Joi.default(%{cron: %{}})

  @impl true
  def state_spec(_opts), do: {:scheduler, @state_schema}

  @impl true
  def directives(_opts), do: [Schedule, Cron, Cancel]

  @impl true
  def reduce(reduction, _opts), do: apply_directives(reduction.plugin_state, reduction.directives)

  @doc "Applies validated Scheduler Directives to the owned state field."
  def apply_directives(state, directives) do
    Enum.reduce_while(directives, {:ok, state}, &apply_directive/2)
  end

  defp apply_directive(%Cron{} = directive, {:ok, state}) do
    spec =
      Scheduler.build_cron_spec(
        directive.cron,
        directive.signal,
        directive.timezone,
        directive.generation
      )

    {:cont, {:ok, put_in(state, [:cron, directive.job_id], spec)}}
  end

  defp apply_directive(%Cancel{job_id: job_id}, {:ok, state}),
    do: {:cont, {:ok, update_in(state, [:cron], &Map.delete(&1, job_id))}}

  defp apply_directive(_other, {:ok, state}), do: {:cont, {:ok, state}}
end
