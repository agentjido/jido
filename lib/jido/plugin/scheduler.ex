defmodule Jido.Plugin.Scheduler do
  @moduledoc """
  Adds delayed and recurring Signals to an Agent.

  The Plugin owns the `:scheduler` part of Agent state. This state contains the
  durable recurring schedule definitions. Its supervised runtime owns timers,
  job references, and other process values.

  A delayed Signal from `schedule/2` is a runtime-only one-shot. It is not in
  Agent state or in a checkpoint. A Scheduler, Agent, or VM restart can discard
  it. Use a recurring durable schedule when work must survive a restart.

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
  The `jido.scheduler.enqueue` route is a trusted internal control route. It does
  not authenticate the Signal source. Do not expose this Signal type to
  untrusted ingress. Valid control Signals for cancelled or replaced generations
  are safe no-ops. Malformed control Signals still fail validation.

  `:delivery_interval` sets the delay between pending-work attempts in milliseconds
  (default 100; positive integer up to 4,294,967,295). One job is tried per attempt.
  Activation and newly queued work can start an immediate attempt. This option
  changes runtime cadence, not occurrence identity, acknowledgement, or skip policy.
  `:delivery_timeout` sets each state-read and delivery call timeout (default
  5,000 milliseconds; positive integer up to 2,147,483,597). External work can
  repeat before acknowledgement, so its receiver must use the occurrence ID to
  handle duplicates.

  `:retry_delay_ms` sets the delay after a recurring job cannot start (default
  1,000; positive integer up to 4,294,967,295). A valid finite cron expression
  with no future occurrence is dormant, not failed. It stays in Agent state so
  it can be cancelled or replaced, and it does not prevent other jobs from
  starting during restore.

  The optional Plugin option `:time_scale` accepts a `SchedEx.TimeScale` module
  with `now/1` and `speedup/0` callbacks for controlled time. Its `speedup/0`
  result must be a positive number, and `now/1` must return a `DateTime`. It
  affects recurring schedules only. The default uses current time. Runtime clock
  state is not saved in the Agent checkpoint.
  """

  use Jido.Plugin,
    agent: Jido.Plugin.Scheduler.Agent,
    agent_server: Jido.Plugin.Scheduler.Server

  alias Crontab.CronExpression.Parser
  alias Jido.PortableTerm

  alias Jido.Plugin.Scheduler.{
    Acknowledge,
    Cancel,
    Cron,
    Durable,
    Occurrence,
    Schedule
  }

  alias Jido.Signal

  @default_timezone "Etc/UTC"

  @doc "Creates one delayed Signal Directive."
  @spec schedule(non_neg_integer(), Signal.t()) :: Schedule.t()
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

  @doc "Checks that a durable occurrence matches the current Scheduler state."
  @spec admit_occurrence(map(), Signal.t()) :: :ok | {:error, term()}
  defdelegate admit_occurrence(state, signal), to: Durable, as: :admit

  @doc "Confirms a pending durable occurrence with the business state commit."
  @spec acknowledge(String.t()) :: Acknowledge.t()
  def acknowledge(occurrence_id), do: %Acknowledge{occurrence_id: occurrence_id}

  @doc "Creates one recurring schedule cancellation Directive."
  @spec cancel(term()) :: Cancel.t()
  def cancel(job_id), do: %Cancel{job_id: job_id}

  @doc false
  def validate_cron_state(cron, _opts) do
    Enum.reduce_while(cron, :ok, fn {job_id, spec}, :ok ->
      with :ok <- validate_durable_id(job_id),
           {:ok, _timezone} <-
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
    if PortableTerm.valid?(scope), do: :ok, else: {:error, :non_durable_occurrence_scope}
  end

  @doc false
  def validate_occurrence(_signal, nil), do: :ok
  def validate_occurrence(signal, _generation), do: Occurrence.validate_template(signal)

  @doc false
  def validate_cron_spec(cron_expression, message, timezone) do
    with :ok <- validate_cron_expression_type(cron_expression),
         {:ok, timezone} <- validate_timezone_option(timezone),
         :ok <- validate_durable_message(message),
         :ok <- validate_cron_syntax(cron_expression),
         :ok <- validate_timezone_support(timezone) do
      {:ok, timezone}
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

  defp validate_cron_expression_type(cron_expression) when is_binary(cron_expression), do: :ok

  defp validate_cron_expression_type(_cron_expression),
    do: {:error, {:invalid_cron, :invalid_type}}

  defp validate_timezone_option(timezone) when is_nil(timezone) or is_binary(timezone),
    do: {:ok, normalize_timezone_value(timezone)}

  defp validate_timezone_option(_timezone), do: {:error, {:invalid_timezone, :invalid_type}}

  defp normalize_timezone_value(nil), do: @default_timezone
  defp normalize_timezone_value(""), do: @default_timezone
  defp normalize_timezone_value(timezone) when is_binary(timezone), do: timezone

  defp validate_durable_message(message) do
    if PortableTerm.valid?(message),
      do: :ok,
      else: {:error, {:invalid_message, :non_durable_term}}
  end

  @doc false
  def validate_durable_id(id) do
    if PortableTerm.valid?(id),
      do: :ok,
      else: {:error, {:invalid_job_id, :non_durable_term}}
  end
end
