defmodule Jido.Plugin.Timer.Every do
  @moduledoc "Creates or replaces one recurring fixed-delay Signal schedule."

  alias Jido.Codec.Term
  alias Jido.Error
  alias Jido.Joi
  alias Jido.Plugin.Timer.{CronRules, Occurrence}
  alias Jido.Signal

  @timer_max 4_294_967_295

  @schema Joi.struct(
            __MODULE__,
            %{
              job_id: Joi.any(description: "Agent-local job id"),
              interval_ms:
                Joi.integer(description: "Positive fixed delay in milliseconds")
                |> Joi.min(1)
                |> Joi.max(@timer_max),
              signal: Joi.struct(Jido.Signal, description: "Signal to send"),
              generation:
                Joi.integer(description: "Optional explicit generation for occurrence metadata")
                |> Joi.min(0)
                |> Joi.max(2_147_483_647)
                |> Joi.nullable()
                |> Joi.optional()
            },
            coerce: true
          )

  @typedoc "A recurring fixed-delay Signal Directive."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one recurring interval schedule request."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Jido.Agent.Directive.parse(@schema, Map.from_struct(directive)),
         :ok <- CronRules.to_error(CronRules.validate_job_id(directive.job_id)),
         generation <- directive.generation || 0,
         :ok <- to_error(validate_spec(directive.interval_ms, directive.signal, generation)) do
      {:ok, directive}
    end
  end

  @doc false
  @spec build_spec(pos_integer(), Signal.t(), non_neg_integer()) :: map()
  def build_spec(interval_ms, %Signal{} = message, generation) do
    %{interval_ms: interval_ms, message: message, generation: generation, status: :running}
  end

  @doc false
  @spec validate_state(map(), keyword()) :: :ok | {:error, String.t()}
  def validate_state(every, _opts) do
    Enum.reduce_while(every, :ok, fn {job_id, spec}, :ok ->
      with :ok <- CronRules.validate_job_id(job_id),
           :ok <- validate_spec(spec.interval_ms, spec.message, spec.generation),
           true <- spec.status in [:running, :paused] do
        {:cont, :ok}
      else
        false -> {:halt, {:error, "invalid interval status for #{inspect(job_id)}"}}
        {:error, reason} -> {:halt, {:error, "invalid interval state for #{inspect(job_id)}: #{inspect(reason)}"}}
      end
    end)
  end

  defp validate_spec(interval_ms, message, generation) do
    with :ok <- validate_interval(interval_ms),
         :ok <- validate_message(message),
         :ok <- validate_generation(generation),
         do: Occurrence.validate_template(message)
  end

  defp validate_interval(value) when is_integer(value) and value in 1..@timer_max, do: :ok
  defp validate_interval(value), do: {:error, {:invalid_interval, value}}

  defp validate_message(%Signal{} = message) do
    if Term.valid?(message), do: :ok, else: {:error, {:invalid_message, :nonportable_term}}
  end

  defp validate_message(_message), do: {:error, {:invalid_message, :invalid_type}}

  defp validate_generation(value) when is_integer(value) and value in 0..2_147_483_647, do: :ok
  defp validate_generation(value), do: {:error, {:invalid_generation, value}}

  defp to_error({:error, {code, reason}}),
    do: Error.validation_result(code, [], error_message(code), %{reason: reason})

  defp to_error({:error, code}) when is_atom(code),
    do: Error.validation_result(code, [], error_message(code))

  defp to_error(result), do: result

  defp error_message(:invalid_interval), do: "Interval must be a positive bounded millisecond value"
  defp error_message(:invalid_message), do: "Interval Signal must be portable data"
  defp error_message(:invalid_generation), do: "Interval generation is invalid"
  defp error_message(:reserved_occurrence_metadata), do: "Interval Signal uses reserved occurrence metadata"
end
