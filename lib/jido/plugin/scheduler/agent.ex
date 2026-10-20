defmodule Jido.Plugin.Scheduler.Agent do
  @moduledoc "Owns recurring schedule definitions in Agent state."
  @behaviour Jido.Plugin

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Cancel, Cron, Schedule}
  alias Jido.Signal

  @timer_max 4_294_967_295
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
  def state_spec(opts) do
    reject_delivery_options!(opts)
    validate_timer_option!(opts, :retry_delay_ms, 1_000, @timer_max)
    validate_time_scale_option!(opts)
    {:scheduler, @state_schema}
  end

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

  defp reject_delivery_options!(opts) do
    if Enum.any?([:delivery_interval, :delivery_timeout], &Keyword.has_key?(opts, &1)) do
      raise ArgumentError, "Scheduler delivery options are not supported"
    end
  end

  defp validate_timer_option!(opts, name, default, maximum) do
    value = Keyword.get(opts, name, default)

    unless is_integer(value) and value in 1..maximum do
      raise ArgumentError, "Scheduler #{name} must be an integer from 1 to #{maximum}"
    end
  end

  defp validate_time_scale_option!(opts) do
    time_scale = Keyword.get(opts, :time_scale, SchedEx.IdentityTimeScale)

    valid? =
      is_atom(time_scale) and not is_nil(time_scale) and Code.ensure_loaded?(time_scale) and
        Enum.all?(SchedEx.TimeScale.behaviour_info(:callbacks), fn {callback, arity} ->
          function_exported?(time_scale, callback, arity)
        end)

    unless valid? do
      raise ArgumentError,
            "Scheduler time_scale must be a loaded module with now/1 and speedup/0 callbacks"
    end
  end
end
