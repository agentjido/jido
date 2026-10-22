defmodule Jido.Plugin.Scheduler.Agent do
  @moduledoc false
  @behaviour Jido.Plugin

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Cancel, Cron, Schedule}
  alias Jido.Signal

  @cron_spec_schema Zoi.object(
                      %{
                        cron_expression: Zoi.string(),
                        message: Zoi.struct(Signal),
                        timezone: Zoi.string(),
                        generation:
                          Zoi.integer() |> Zoi.min(0) |> Zoi.max(2_147_483_647) |> Zoi.optional()
                      },
                      unrecognized_keys: :error
                    )
  @state_schema Zoi.object(%{
                  cron:
                    Zoi.map(Zoi.any(), @cron_spec_schema,
                      description: "Recurring schedule definitions"
                    )
                    |> Zoi.refine({Scheduler, :validate_cron_state, []})
                })
                |> Zoi.default(%{cron: %{}})

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
