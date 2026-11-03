defmodule Jido.Plugin.Scheduler.CronRules do
  @moduledoc false

  alias Crontab.CronExpression.Parser
  alias Jido.Codec.Term
  alias Jido.Plugin.Scheduler.Occurrence
  alias Jido.Signal

  @default_timezone "Etc/UTC"

  @spec build_spec(String.t(), term(), String.t() | nil, non_neg_integer() | nil) :: map()
  def build_spec(cron_expression, message, timezone \\ nil, generation \\ nil)
      when is_binary(cron_expression) and (is_nil(timezone) or is_binary(timezone)) do
    spec = %{
      cron_expression: cron_expression,
      message: message,
      timezone: normalize_timezone_value(timezone)
    }

    if is_nil(generation), do: spec, else: Map.put(spec, :generation, generation)
  end

  @spec validate_state(map(), keyword()) :: :ok | {:error, String.t()}
  def validate_state(cron, _opts) do
    Enum.reduce_while(cron, :ok, fn {job_id, spec}, :ok ->
      with :ok <- validate_job_id(job_id),
           {:ok, _timezone} <- validate_spec(spec.cron_expression, spec.message, spec.timezone),
           :ok <- validate_occurrence(spec.message, Map.get(spec, :generation)) do
        {:cont, :ok}
      else
        {:error, reason} ->
          {:halt, {:error, "invalid cron state for #{inspect(job_id)}: #{inspect(reason)}"}}
      end
    end)
  end

  @spec validate_spec(term(), term(), term()) :: {:ok, String.t()} | {:error, term()}
  def validate_spec(cron_expression, message, timezone) do
    with :ok <- validate_cron_expression_type(cron_expression),
         {:ok, timezone} <- validate_timezone_option(timezone),
         :ok <- validate_message(message),
         :ok <- validate_cron_syntax(cron_expression),
         :ok <- validate_timezone_support(timezone) do
      {:ok, timezone}
    end
  end

  @spec validate_job_id(term()) :: :ok | {:error, term()}
  def validate_job_id(id) do
    if Term.valid?(id),
      do: :ok,
      else: {:error, {:invalid_job_id, :nonportable_term}}
  end

  @spec validate_occurrence_scope(term()) :: :ok | {:error, term()}
  def validate_occurrence_scope(scope) do
    if Term.valid?(scope), do: :ok, else: {:error, :nonportable_occurrence_scope}
  end

  @spec validate_occurrence(Signal.t(), non_neg_integer() | nil) :: :ok | {:error, term()}
  def validate_occurrence(_signal, nil), do: :ok
  def validate_occurrence(signal, _generation), do: Occurrence.validate_template(signal)

  @spec occurrence_signal(Signal.t(), term(), term(), non_neg_integer() | nil, DateTime.t()) ::
          {:ok, Signal.t()} | {:error, term()}
  def occurrence_signal(%Signal{} = signal, scope, job_id, nil, %DateTime{} = scheduled_at),
    do: occurrence_signal(signal, scope, job_id, 0, scheduled_at)

  def occurrence_signal(
        %Signal{} = signal,
        scope,
        job_id,
        generation,
        %DateTime{} = scheduled_at
      )
      when is_integer(generation) and generation in 0..2_147_483_647 do
    with :ok <- validate_occurrence_scope(scope),
         :ok <- validate_job_id(job_id),
         :ok <- Occurrence.validate_template(signal) do
      Occurrence.attach(fresh_signal(signal), scope, job_id, generation, scheduled_at)
    end
  end

  def occurrence_signal(_signal, _scope, _job_id, _generation, _scheduled_at),
    do: {:error, :invalid_schedule_occurrence}

  @spec next_occurrence(String.t(), String.t(), DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def next_occurrence(expression, timezone, %DateTime{} = after_time)
      when is_binary(expression) and is_binary(timezone) do
    extended? = length(String.split(expression)) > 5

    with {:ok, cron} <- Parser.parse(expression, extended?),
         {:ok, local_after} <- DateTime.shift_zone(after_time, timezone) do
      next_strict(cron, timezone, local_after, after_time)
    end
  rescue
    _exception -> {:error, :invalid_cron_boundary}
  catch
    _kind, _reason -> {:error, :invalid_cron_boundary}
  end

  def next_occurrence(_expression, _timezone, _after_time),
    do: {:error, :invalid_cron_boundary}

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

  defp validate_message(message) do
    if Term.valid?(message),
      do: :ok,
      else: {:error, {:invalid_message, :nonportable_term}}
  end

  defp fresh_signal(%Signal{} = signal) do
    signal
    |> Jido.Codec.Signal.to_map()
    |> Map.delete("id")
    |> Signal.new!()
  end

  defp next_local(cron, timezone, local_after) do
    case Crontab.Scheduler.get_next_run_date(cron, DateTime.to_naive(local_after)) do
      {:ok, naive_next} -> to_utc(cron, timezone, naive_next)
      {:error, _reason} = error -> error
    end
  end

  defp next_strict(cron, timezone, local_after, after_time) do
    with {:ok, next} <- next_local(cron, timezone, local_after) do
      if DateTime.compare(next, after_time) == :gt do
        {:ok, next}
      else
        next_local(cron, timezone, DateTime.add(local_after, 1, :microsecond))
      end
    end
  end

  defp to_utc(cron, timezone, naive_next) do
    case DateTime.from_naive(naive_next, timezone) do
      {:ok, next} -> DateTime.shift_zone(next, "Etc/UTC")
      {:ambiguous, _first, second} -> DateTime.shift_zone(second, "Etc/UTC")
      {:gap, _before, just_after} -> next_local(cron, timezone, just_after)
      {:error, _reason} = error -> error
    end
  end
end
