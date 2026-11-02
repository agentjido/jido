defmodule Jido.Flow.Call do
  @moduledoc """
  The canonical data for one Action or child Flow call.

  A Call contains one `Jido.Instruction`, an optional Action attempt policy,
  and its result error policy. A Step in the Flow DSL normalizes to this data.
  """

  alias Jido.Flow.{CallPolicy, Error, Value}
  alias Jido.Instruction

  @type t :: %__MODULE__{
          instruction: Instruction.t(),
          policy: CallPolicy.t(),
          on_error: on_error()
        }
  @type on_error :: :fail_fast | :collect_errors

  @enforce_keys [:instruction]
  defstruct [:instruction, policy: %{}, on_error: :fail_fast]

  @fields [
    :type,
    :action,
    :instruction,
    :params,
    :context,
    :metadata,
    :policy,
    :timeout_ms,
    :retry,
    :on_error
  ]

  @doc false
  @spec from_options(term(), map(), map(), term(), term(), term(), term()) ::
          {:ok, t()} | {:error, Exception.t()}
  def from_options(target, params, metadata, policy, timeout_ms, retry, on_error) do
    with {:ok, instruction} <-
           Instruction.new(target: target, params: params, metadata: metadata),
         {:ok, policy} <- CallPolicy.from_options(policy, timeout_ms, retry),
         do: new(instruction, policy, on_error)
  end

  @doc false
  @spec from_options(term(), map(), map(), term(), term(), term()) ::
          {:ok, t()} | {:error, Exception.t()}
  def from_options(target, params, metadata, timeout_ms, retry, on_error \\ :fail_fast) do
    from_options(target, params, metadata, nil, timeout_ms, retry, on_error)
  end

  @doc false
  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, Exception.t()}
  def new(instruction, policy \\ %{}, on_error \\ :fail_fast),
    do:
      normalize(
        %__MODULE__{instruction: instruction, policy: policy, on_error: on_error},
        :any,
        "Flow"
      )

  @doc false
  @spec new!(term(), term(), term()) :: t() | no_return()
  def new!(instruction, policy \\ %{}, on_error \\ :fail_fast) do
    case new(instruction, policy, on_error) do
      {:ok, call} -> call
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec normalize(term(), Jido.Flow.Ref.scope(), String.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def normalize(value, scope, label)

  def normalize(%__MODULE__{} = call, scope, label),
    do: normalize_parts(call.instruction, call.policy, call.on_error, scope, label)

  def normalize(%{} = attrs, scope, label) when not is_struct(attrs) do
    if call_map?(attrs) do
      normalize_map(attrs, scope, label)
    else
      normalize_parts(attrs, %{}, :fail_fast, scope, label)
    end
  end

  def normalize(value, scope, label),
    do: normalize_parts(value, %{}, :fail_fast, scope, label)

  @doc false
  @spec canonical?(term(), Jido.Flow.Ref.scope(), String.t()) :: boolean()
  def canonical?(call, scope, label) do
    case normalize(call, scope, label) do
      {:ok, ^call} -> true
      _other -> false
    end
  end

  @doc false
  @spec result_refs(t()) :: [String.t()]
  def result_refs(%__MODULE__{instruction: instruction}) do
    Value.result_refs(instruction.params) ++ Value.result_refs(instruction.context)
  end

  @doc false
  @spec target(t()) :: Instruction.target()
  def target(%__MODULE__{instruction: instruction}), do: instruction.target

  @doc false
  @spec with_instruction(t(), Instruction.t()) :: t()
  def with_instruction(%__MODULE__{} = call, %Instruction{} = instruction),
    do: %{call | instruction: instruction}

  @doc false
  @spec with_on_error(t(), on_error()) :: t()
  def with_on_error(%__MODULE__{} = call, on_error)
      when on_error in [:fail_fast, :collect_errors],
      do: %{call | on_error: on_error}

  defp normalize_map(attrs, scope, label) do
    with {:ok, attrs} <- normalize_fields(attrs, label),
         :ok <- validate_type(attrs, label),
         {:ok, instruction} <- instruction(attrs, label),
         {:ok, policy} <- policy(attrs, label),
         {:ok, on_error} <- on_error(attrs, label) do
      normalize_parts(instruction, policy, on_error, scope, label)
    end
  end

  defp normalize_parts(value, policy, on_error, scope, label) do
    with {:ok, instruction} <- Instruction.normalize(value),
         {:ok, params} <- Value.prepare(instruction.params, scope),
         {:ok, context} <- Value.prepare(instruction.context, scope),
         :ok <- Value.validate_object(instruction.metadata),
         {:ok, policy} <- CallPolicy.normalize(policy),
         {:ok, on_error} <- validate_on_error(on_error, label),
         :ok <- validate_policy_target(instruction, policy),
         {:ok, instruction} <-
           Instruction.new(
             target: instruction.target,
             params: params,
             context: context,
             metadata: instruction.metadata
           ) do
      {:ok, %__MODULE__{instruction: instruction, policy: policy, on_error: on_error}}
    else
      {:error, %Instruction.Error{} = error} ->
        {:error,
         Error.validation_error("invalid #{label} Instruction", %{
           reason: :instruction,
           cause: error
         })}

      error ->
        error
    end
  end

  defp normalize_fields(attrs, label) do
    attrs
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      normalized_key = if is_binary(key), do: key_to_field(key), else: key

      cond do
        normalized_key not in @fields ->
          {:halt,
           {:error,
            Error.validation_error("#{label} call contains an unknown field", %{
              reason: :unknown_field,
              field: key
            })}}

        Map.has_key?(normalized, normalized_key) ->
          {:halt,
           {:error,
            Error.validation_error("#{label} call contains a duplicate field", %{
              reason: :duplicate_field,
              field: normalized_key
            })}}

        true ->
          {:cont, {:ok, Map.put(normalized, normalized_key, value)}}
      end
    end)
  end

  defp validate_type(%{type: type}, _label) when type in [:call, "call"], do: :ok
  defp validate_type(%{type: type}, label), do: invalid(label, :type, type)
  defp validate_type(_attrs, _label), do: :ok

  defp instruction(%{instruction: instruction} = attrs, label) do
    mixed = Enum.filter([:action, :params, :context, :metadata], &Map.has_key?(attrs, &1))

    if mixed == [] do
      {:ok, instruction}
    else
      invalid(label, :instruction, %{mixed_fields: mixed})
    end
  end

  defp instruction(%{action: target} = attrs, _label) do
    Instruction.new(
      target: target,
      params: Map.get(attrs, :params, %{}),
      context: Map.get(attrs, :context, %{}),
      metadata: Map.get(attrs, :metadata, %{})
    )
  end

  defp instruction(_attrs, label), do: invalid(label, :instruction_required, nil)

  defp policy(attrs, _label) do
    CallPolicy.from_options(
      Map.get(attrs, :policy),
      Map.get(attrs, :timeout_ms),
      Map.get(attrs, :retry)
    )
  end

  defp on_error(attrs, label),
    do: validate_on_error(Map.get(attrs, :on_error, :fail_fast), label)

  defp validate_on_error(on_error, _label)
       when on_error in [:fail_fast, :collect_errors],
       do: {:ok, on_error}

  defp validate_on_error(on_error, label), do: invalid(label, :on_error, on_error)

  defp validate_policy_target(_instruction, policy) when map_size(policy) == 0, do: :ok

  defp validate_policy_target(instruction, _policy) do
    case Instruction.target_kind(instruction) do
      {:ok, :action} ->
        :ok

      {:ok, :flow} ->
        {:error,
         Error.validation_error("Flow call policy supports Action targets only", %{
           reason: :unsupported_flow_call_policy,
           target: instruction.target
         })}

      {:error, error} ->
        {:error, error}
    end
  end

  defp call_map?(attrs) do
    Enum.any?(
      [
        :type,
        "type",
        :action,
        "action",
        :instruction,
        "instruction",
        :policy,
        "policy",
        :on_error,
        "on_error"
      ],
      &Map.has_key?(attrs, &1)
    )
  end

  defp key_to_field(key), do: Enum.find(@fields, &(Atom.to_string(&1) == key))

  defp invalid(label, reason, value) do
    {:error,
     Error.validation_error("#{label} call is invalid", %{
       reason: reason,
       value: value
     })}
  end
end
