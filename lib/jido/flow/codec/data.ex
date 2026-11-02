defmodule Jido.Flow.Codec.Data do
  @moduledoc false

  alias Jido.Authoring.Registry
  alias Jido.Flow.{Call, CallPolicy, Error}
  alias Jido.Flow.Codec.Value
  alias Jido.Instruction

  @instruction_fields ["target", "params", "context", "metadata"]
  @call_fields ["instruction", "policy", "on_error"]

  @doc false
  @spec call_fields() :: [String.t()]
  def call_fields, do: @call_fields

  @doc false
  @spec encode_call(Call.t(), Registry.t()) :: {:ok, map()} | {:error, Exception.t()}
  def encode_call(%Call{} = call, registry) do
    with {:ok, instruction} <- encode_instruction(call.instruction, registry) do
      {:ok,
       %{
         "instruction" => instruction,
         "policy" => encode_policy(call.policy),
         "on_error" => Atom.to_string(call.on_error)
       }}
    end
  end

  @doc false
  @spec decode_call(term(), Registry.t(), list()) ::
          {:ok, map()} | {:error, [Exception.t()]}
  def decode_call(%{} = record, registry, path) when not is_struct(record) do
    with :ok <- exact_fields(record, @call_fields, path),
         {:ok, instruction_record} <- required(record, "instruction", path),
         {:ok, instruction} <-
           decode_instruction(instruction_record, registry, path ++ ["instruction"]),
         {:ok, policy} <- required(record, "policy", path),
         {:ok, on_error} <-
           decode_on_error(
             Map.get(record, "on_error", "fail_fast"),
             path ++ ["on_error"],
             "Call"
           ) do
      {:ok, %{type: :call, instruction: instruction, policy: policy, on_error: on_error}}
    else
      {:error, errors} when is_list(errors) -> {:error, errors}
    end
  end

  def decode_call(_record, _registry, path),
    do: failure("stored Flow call must be a map", path, :call)

  @doc false
  @spec encode_policy(CallPolicy.t()) :: map()
  def encode_policy(policy) do
    policy
    |> Enum.map(fn
      {:timeout_ms, timeout_ms} -> {"timeout_ms", timeout_ms}
      {:retry, retry} -> {"retry", encode_retry(retry)}
    end)
    |> Map.new()
  end

  @doc false
  @spec decode_value(term(), Registry.t(), list(), :expression | :data) ::
          {:ok, term()} | {:error, [Exception.t()]}
  def decode_value(value, registry, path, mode \\ :expression) do
    case Value.decode(value, registry, path, mode) do
      {:ok, value} -> {:ok, value}
      {:error, errors} -> {:error, errors}
    end
  end

  @doc false
  @spec exact_fields(map(), [String.t()], list()) :: :ok | {:error, [Exception.t()]}
  def exact_fields(record, fields, path) do
    case Map.keys(record) -- fields do
      [] ->
        :ok

      unknown ->
        field = Enum.min(unknown)
        failure("unknown stored Flow field: #{inspect(field)}", path ++ [field], :unknown_field)
    end
  end

  @doc false
  @spec required(map(), String.t(), list()) :: {:ok, term()} | {:error, [Exception.t()]}
  def required(record, field, path) do
    case Map.fetch(record, field) do
      {:ok, value} -> {:ok, value}
      :error -> failure("stored Flow field is required", path ++ [field], :required)
    end
  end

  @doc false
  @spec failure(String.t(), list(), atom()) :: {:error, [Exception.t()]}
  def failure(message, path, reason) do
    {:error, [Error.validation_error(message, %{path: path, reason: reason})]}
  end

  @doc false
  @spec decode_on_error(term(), list(), String.t()) ::
          {:ok, :fail_fast | :collect_errors} | {:error, [Exception.t()]}
  def decode_on_error("fail_fast", _path, _label), do: {:ok, :fail_fast}
  def decode_on_error("collect_errors", _path, _label), do: {:ok, :collect_errors}

  def decode_on_error(_value, path, label),
    do: failure("stored #{label} on_error policy is invalid", path, :on_error)

  @doc false
  @spec decode_reference(term(), term(), Registry.t(), list()) ::
          {:ok, term()} | {:error, [Exception.t()]}
  def decode_reference(value, kind, registry, path) do
    case Registry.decode_reference(registry, value, kind) do
      {:ok, resolved} ->
        {:ok, resolved}

      {:error, %Registry.Error{} = error} ->
        message = String.replace(error.message, "authoring Registry", "Flow Registry")
        {:error, [Error.validation_error(message, Map.put(error.details, :path, path))]}
    end
  end

  defp encode_instruction(%Instruction{} = instruction, registry) do
    with {:ok, target} <-
           Registry.encode_reference(registry, [:action, :flow], instruction.target),
         {:ok, params} <- Value.encode_expression(instruction.params, registry, 0),
         {:ok, context} <- Value.encode_expression(instruction.context, registry, 0),
         {:ok, metadata} <- Value.encode_data(instruction.metadata, registry, 0) do
      {:ok,
       %{
         "target" => target,
         "params" => params,
         "context" => context,
         "metadata" => metadata
       }}
    end
  end

  defp decode_instruction(%{} = record, registry, path) when not is_struct(record) do
    with :ok <- exact_fields(record, @instruction_fields, path),
         {:ok, target_record} <- required(record, "target", path),
         {:ok, target} <-
           decode_reference(target_record, [:action, :flow], registry, path ++ ["target"]),
         {:ok, params_record} <- required(record, "params", path),
         {:ok, params} <- decode_value(params_record, registry, path ++ ["params"]),
         {:ok, context_record} <- required(record, "context", path),
         {:ok, context} <- decode_value(context_record, registry, path ++ ["context"]),
         {:ok, metadata_record} <- required(record, "metadata", path),
         {:ok, metadata} <- decode_value(metadata_record, registry, path ++ ["metadata"], :data),
         {:ok, instruction} <-
           Instruction.new(
             target: target,
             params: params,
             context: context,
             metadata: metadata
           ) do
      {:ok, instruction}
    else
      {:error, errors} when is_list(errors) -> {:error, errors}
      {:error, error} -> {:error, [error]}
    end
  end

  defp decode_instruction(_record, _registry, path),
    do: failure("stored Flow Instruction must be a map", path, :instruction)

  defp encode_retry(retry),
    do: %{
      "max_attempts" => retry.max_attempts,
      "backoff" => Atom.to_string(retry.backoff),
      "base_delay_ms" => retry.base_delay_ms,
      "max_delay_ms" => retry.max_delay_ms
    }
end
