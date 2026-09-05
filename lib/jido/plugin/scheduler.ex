defmodule Jido.Plugin.Scheduler do
  @moduledoc """
  Adds delayed and recurring Signals to an Agent.

  The Plugin owns the `:scheduler` part of Agent state. This state contains the
  durable recurring schedule definitions. Its supervised runtime owns timers,
  job references, and other process values.

  Pass `generation: integer` (0 through 2,147,483,647) to `cron/4` to add logical occurrence
  metadata. Use a new generation when replacing or recreating a schedule, and
  retain it across restore. `occurrence/1` reads the metadata. Signal data stays
  unchanged. Omit generation for the existing plain ticks.

      directive = Jido.Plugin.Scheduler.cron("report", "0 * * * *", tick, generation: 1)

  In the tick Action, read the metadata from `context.signal`:

      {:ok, occurrence} = Jido.Plugin.Scheduler.occurrence(context.signal)
      occurrence.id

  Add `delivery: :durable` to save one pending occurrence per job before its
  business work. Declare the enqueue route in the Agent:

      route "jido.scheduler.enqueue", Jido.Plugin.Scheduler.Enqueue

  Return `acknowledge(occurrence.id)` with the business Action's next state.
  That commit removes pending work. Failed Turns retain it for retry. Completed,
  cancelled, and replaced durable ticks are rejected before execution.

  Durable delivery needs Agent persistence for recovery after Agent or VM loss.
  The fixed policy skips slots while a job is pending and slots missed offline.
  It retries saved pending work every 100 milliseconds, one job per attempt.
  `:delivery_timeout` sets each state-read and delivery call timeout (default
  5,000 milliseconds). External work can repeat before acknowledgement, so its
  receiver must use the occurrence ID to handle duplicates.

  The optional Plugin option `:time_scale` accepts a `SchedEx.TimeScale` module
  for controlled time. It affects recurring schedules only. The default uses
  current time. Runtime clock state is not saved in the Agent checkpoint.
  """

  use Jido.Plugin

  alias Crontab.CronExpression.Parser
  alias Jido.Plugin.{DirectiveContext, Init}

  alias Jido.Plugin.Scheduler.{
    Acknowledge,
    Cancel,
    Cron,
    Durable,
    Occurrence,
    Queue,
    Runtime,
    Schedule
  }

  alias Jido.Signal

  @state_key :scheduler
  @default_timezone "Etc/UTC"
  @cron_spec_schema Zoi.object(%{
                      cron_expression: Zoi.string(),
                      message: Zoi.struct(Jido.Signal),
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
                    |> Zoi.refine({__MODULE__, :validate_cron_state, []})
                })
                |> Zoi.default(%{cron: %{}})

  @doc "Creates one delayed Signal Directive."
  @spec schedule(non_neg_integer(), Signal.t()) :: Schedule.t()
  def schedule(delay_ms, %Signal{} = signal), do: %Schedule{delay_ms: delay_ms, signal: signal}

  def schedule(delay_ms, signal), do: %Schedule{delay_ms: delay_ms, signal: signal}

  @doc "Creates one recurring Signal Directive."
  @spec cron(term(), String.t(), Signal.t(), keyword()) :: Cron.t()
  def cron(job_id, cron, signal, opts \\ []) do
    %Cron{
      job_id: job_id,
      cron: cron,
      signal: signal,
      timezone: Keyword.get(opts, :timezone),
      generation: Keyword.get(opts, :generation),
      delivery: Keyword.get(opts, :delivery, :best_effort)
    }
  end

  @doc "Reads logical occurrence metadata from a recurring tick."
  @spec occurrence(Signal.t()) :: {:ok, Occurrence.t()} | {:error, term()}
  defdelegate occurrence(signal), to: Occurrence, as: :from_signal

  @doc "Confirms a pending durable occurrence with the business state commit."
  @spec acknowledge(String.t()) :: Acknowledge.t()
  def acknowledge(occurrence_id), do: %Acknowledge{occurrence_id: occurrence_id}

  @impl Jido.Plugin
  def prepare(command, _opts) do
    if Durable.marked?(command.signal) do
      with :ok <- Durable.admit(command.agent.state.scheduler, command.signal), do: {:ok, command}
    else
      {:ok, command}
    end
  end

  @doc "Creates one recurring schedule cancellation Directive."
  @spec cancel(term()) :: Cancel.t()
  def cancel(job_id), do: %Cancel{job_id: job_id}

  @impl Jido.Plugin
  def state_spec(_opts), do: {@state_key, @state_schema}

  @doc false
  def validate_cron_state(cron, _opts) do
    Enum.reduce_while(cron, :ok, fn {job_id, spec}, :ok ->
      with :ok <- validate_durable_id(job_id),
           {:ok, _validated} <-
             validate_cron_spec(spec.cron_expression, spec.message, spec.timezone),
           :ok <- validate_occurrence(spec.message, Map.get(spec, :generation)),
           :ok <- validate_durable_message(Map.get(spec, :pending)),
           :ok <- Durable.validate(spec) do
        {:cont, :ok}
      else
        {:error, reason} ->
          {:halt, {:error, "invalid cron state for #{inspect(job_id)}: #{inspect(reason)}"}}
      end
    end)
  end

  @impl Jido.Plugin
  def update_state(state, directives, _opts) do
    Enum.reduce_while(directives, {:ok, state}, fn
      %Cron{} = directive, {:ok, state} ->
        spec =
          build_cron_spec(
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

      _directive, {:ok, state} ->
        {:cont, {:ok, state}}
    end)
  end

  @impl Jido.Plugin
  def directives(_opts), do: [Schedule, Cron, Cancel, Queue, Acknowledge]

  @impl Jido.Plugin
  def validate_directive(%Schedule{} = directive, _opts),
    do: Zoi.parse(Schedule.schema(), Map.from_struct(directive))

  def validate_directive(%Cron{} = directive, _opts) do
    with {:ok, directive} <- Zoi.parse(Cron.schema(), Map.from_struct(directive)),
         :ok <- validate_durable_id(directive.job_id),
         {:ok, spec} <-
           validate_cron_spec(directive.cron, directive.signal, directive.timezone),
         :ok <- validate_occurrence(directive.signal, directive.generation),
         :ok <- validate_delivery(directive) do
      {:ok, %{directive | timezone: spec.timezone}}
    end
  end

  def validate_directive(%Cancel{} = directive, _opts) do
    with {:ok, directive} <- Zoi.parse(Cancel.schema(), Map.from_struct(directive)),
         :ok <- validate_durable_id(directive.job_id) do
      {:ok, directive}
    end
  end

  def validate_directive(%Queue{} = directive, _opts) do
    with {:ok, directive} <- Zoi.parse(Queue.schema(), Map.from_struct(directive)),
         :ok <- validate_durable_id(directive.job_id),
         :ok <- validate_occurrence_scope(directive.scope) do
      {:ok, directive}
    end
  end

  def validate_directive(%Acknowledge{} = directive, _opts),
    do: Zoi.parse(Acknowledge.schema(), Map.from_struct(directive))

  def validate_directive(directive, _opts) do
    {:error,
     Jido.Error.validation_error("Unknown Scheduler Plugin Directive",
       details: %{directive: directive}
     )}
  end

  @impl Jido.Plugin
  def dispatch(runtime, %module{}, _context, _opts) when module in [Queue, Acknowledge],
    do: GenServer.cast(runtime, :pending_changed)

  def dispatch(runtime, directive, %DirectiveContext{} = context, opts) do
    GenServer.call(runtime, {:directive, directive, context}, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:scheduler_runtime_unavailable, reason}}
  end

  @impl Jido.Plugin
  def await_ready(runtime, opts) do
    GenServer.call(runtime, :await_ready, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:scheduler_runtime_unavailable, reason}}
  end

  @doc false
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end

  @doc false
  @spec build_cron_spec(
          String.t(),
          term(),
          String.t() | nil,
          non_neg_integer() | nil,
          :best_effort | :durable
        ) :: map()
  def build_cron_spec(
        cron_expression,
        message,
        timezone \\ nil,
        generation \\ nil,
        delivery \\ :best_effort
      )
      when is_binary(cron_expression) and (is_nil(timezone) or is_binary(timezone)) do
    spec = %{
      cron_expression: cron_expression,
      message: message,
      timezone: normalize_timezone_value(timezone)
    }

    spec = if is_nil(generation), do: spec, else: Map.put(spec, :generation, generation)

    if delivery == :durable,
      do: Map.merge(spec, %{delivery: :durable, pending: nil, last_scheduled_at: nil}),
      else: spec
  end

  @doc false
  def validate_occurrence_scope(scope) do
    if durable_term?(scope), do: :ok, else: {:error, :non_durable_occurrence_scope}
  end

  defp validate_occurrence(_signal, nil), do: :ok
  defp validate_occurrence(signal, _generation), do: Occurrence.validate_template(signal)

  defp validate_delivery(%Cron{delivery: :durable, generation: nil}),
    do: {:error, :durable_schedule_requires_generation}

  defp validate_delivery(_directive), do: :ok

  defp validate_cron_spec(cron_expression, message, timezone) do
    with {:ok, spec} <- validate_and_build_cron_spec(cron_expression, message, timezone),
         :ok <- validate_cron_syntax(spec.cron_expression),
         :ok <- validate_timezone_support(spec.timezone) do
      {:ok, spec}
    end
  end

  defp validate_cron_syntax(cron_expression) do
    extended? = length(String.split(cron_expression)) > 5

    case Parser.parse(cron_expression, extended?) do
      {:ok, _expression} -> :ok
      {:error, reason} -> {:error, {:invalid_cron, reason}}
    end
  end

  defp validate_timezone_support(timezone) do
    case DateTime.now(timezone) do
      {:ok, _now} -> :ok
      {:error, reason} -> {:error, {:invalid_timezone, reason}}
    end
  end

  defp validate_and_build_cron_spec(cron_expression, message, timezone) do
    with :ok <- validate_cron_expression_type(cron_expression),
         {:ok, normalized_timezone} <- validate_timezone_option(timezone),
         :ok <- validate_durable_message(message) do
      {:ok,
       %{
         cron_expression: cron_expression,
         message: message,
         timezone: normalized_timezone
       }}
    end
  end

  defp validate_cron_expression_type(cron_expression) when is_binary(cron_expression), do: :ok

  defp validate_cron_expression_type(_cron_expression),
    do: {:error, {:invalid_cron, :invalid_type}}

  defp validate_timezone_option(nil), do: {:ok, @default_timezone}
  defp validate_timezone_option(""), do: {:ok, @default_timezone}
  defp validate_timezone_option(timezone) when is_binary(timezone), do: {:ok, timezone}
  defp validate_timezone_option(_timezone), do: {:error, {:invalid_timezone, :invalid_type}}

  defp normalize_timezone_value(nil), do: @default_timezone
  defp normalize_timezone_value(""), do: @default_timezone
  defp normalize_timezone_value(timezone) when is_binary(timezone), do: timezone

  defp validate_durable_message(message) do
    if durable_term?(message), do: :ok, else: {:error, {:invalid_message, :non_durable_term}}
  end

  defp validate_durable_id(id) do
    if durable_term?(id), do: :ok, else: {:error, {:invalid_job_id, :non_durable_term}}
  end

  defp durable_term?(term)
       when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
       do: false

  defp durable_term?(term) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.all?(fn {key, value} -> durable_term?(key) and durable_term?(value) end)
  end

  defp durable_term?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.all?(&durable_term?/1)

  defp durable_term?(term) when is_list(term), do: Enum.all?(term, &durable_term?/1)
  defp durable_term?(_term), do: true
end
