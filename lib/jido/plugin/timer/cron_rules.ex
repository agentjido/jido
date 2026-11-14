defmodule Jido.Plugin.Timer.CronRules do
  @moduledoc false

  alias Crontab.CronExpression.Parser
  alias Jido.Codec.Term
  alias Jido.Error
  alias Jido.Plugin.Timer.Occurrence
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

  @doc "Converts a rule failure to the public Directive error. Other results pass through."
  @spec to_error(term()) :: term()
  def to_error({:error, {code, reason}}),
    do: Error.validation_result(code, [], error_message(code), %{reason: reason})

  def to_error({:error, code}) when is_atom(code),
    do: Error.validation_result(code, [], error_message(code))

  def to_error(result), do: result

  defp error_message(:invalid_cron), do: "Invalid cron expression"
  defp error_message(:invalid_timezone), do: "Invalid timezone"
  defp error_message(:invalid_job_id), do: "Cron job ID must be portable data"
  defp error_message(:invalid_message), do: "Cron Signal must be portable data"
  defp error_message(:reserved_occurrence_metadata), do: "Cron Signal uses reserved occurrence metadata"

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
end
