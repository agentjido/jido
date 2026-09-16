defmodule Jido.Plugin.Scheduler.Agent do
  @moduledoc "Owns recurring schedules and pending occurrences in Agent state."
  use Jido.Agent.Plugin

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Acknowledge, Cancel, Cron, Durable, Occurrence, Queue, Schedule}
  alias Jido.Signal

  @timer_max 4_294_967_295
  @delivery_timeout_max div(@timer_max - 100, 2)
  @cron_spec_schema Zoi.object(%{
                      cron_expression: Zoi.string(),
                      message: Zoi.struct(Signal),
                      timezone: Zoi.string(),
                      generation:
                        Zoi.integer() |> Zoi.min(0) |> Zoi.max(2_147_483_647) |> Zoi.optional(),
                      delivery: Zoi.literal(:durable) |> Zoi.optional(),
                      pending: Zoi.struct(Signal) |> Zoi.nullable() |> Zoi.optional(),
                      last_scheduled_at:
                        Zoi.string()
                        |> Zoi.refine({Occurrence, :validate_utc, []})
                        |> Zoi.nullable()
                        |> Zoi.optional()
                    })
  @state_schema Zoi.object(%{
                  cron:
                    Zoi.map(Zoi.any(), @cron_spec_schema,
                      description: "Durable recurring schedule definitions"
                    )
                    |> Zoi.refine({Scheduler, :validate_cron_state, []})
                })
                |> Zoi.default(%{cron: %{}})

  @impl true
  def state_spec(opts) do
    validate_timer_option!(opts, :delivery_interval, 100, @timer_max)
    validate_timer_option!(opts, :delivery_timeout, 5_000, @delivery_timeout_max)
    validate_timer_option!(opts, :retry_delay_ms, 1_000, @timer_max)
    validate_time_scale_option!(opts)
    {:scheduler, @state_schema}
  end

  @impl true
  def directives(_opts), do: [Schedule, Cron, Cancel, Queue, Acknowledge]

  @impl true
  def reduce(reduction, _opts), do: apply_directives(reduction.plugin_state, reduction.directives)

  @doc "Applies validated Scheduler Directives to the owned state field."
  def apply_directives(state, directives) do
    Enum.reduce_while(directives, {:ok, state}, fn
      %Cron{} = directive, {:ok, state} ->
        spec =
          Scheduler.build_cron_spec(
            directive.cron,
            directive.signal,
            directive.timezone,
            directive.generation,
            directive.delivery
          )

        case Durable.replace(Map.get(state.cron, directive.job_id), spec) do
          {:ok, spec} -> {:cont, {:ok, put_in(state, [:cron, directive.job_id], spec)}}
          error -> {:halt, error}
        end

      %Cancel{job_id: job_id}, {:ok, state} ->
        {:cont, {:ok, update_in(state, [:cron], &Map.delete(&1, job_id))}}

      %module{} = directive, {:ok, state} when module in [Queue, Acknowledge] ->
        case Durable.update(state, directive) do
          {:ok, state} -> {:cont, {:ok, state}}
          error -> {:halt, error}
        end

      _other, {:ok, state} ->
        {:cont, {:ok, state}}
    end)
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
