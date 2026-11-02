defmodule Jido.Flow.Form.Invoke do
  @moduledoc """
  The canonical form for one closed dynamic call.

  Invoke selects one Action or Flow target by string ID. The target table is
  fixed in the Flow definition. Runtime selection does not change the graph.
  """

  alias Jido.Flow.{CallPolicy, Error, Limits, Value}
  alias Jido.Flow.Form.Validation
  alias Jido.Instruction

  @type target_id :: String.t()
  @type targets :: %{required(target_id()) => Instruction.target()}
  @type t :: %__MODULE__{
          target: Value.t(),
          targets: targets(),
          params: Value.t(),
          metadata: map(),
          policy: CallPolicy.t(),
          on_error: Jido.Flow.Call.on_error()
        }

  @fields [
    :type,
    :target,
    :targets,
    :params,
    :meta,
    :policy,
    :timeout_ms,
    :retry,
    :on_error
  ]

  @enforce_keys [:target, :targets]
  defstruct [:target, :targets, params: %{}, metadata: %{}, policy: %{}, on_error: :fail_fast]

  @doc false
  @spec new(term(), term(), term(), term(), term(), term()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new(target, targets, params \\ %{}, metadata \\ %{}, policy \\ %{}, on_error \\ :fail_fast) do
    normalize(%__MODULE__{
      target: target,
      targets: targets,
      params: params,
      metadata: metadata,
      policy: policy,
      on_error: on_error
    })
  end

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%__MODULE__{} = invoke) do
    with {:ok, target} <- Value.prepare(invoke.target, :flow),
         {:ok, params} <- Value.prepare(invoke.params, :flow),
         :ok <- Value.validate_object(invoke.metadata),
         {:ok, policy} <- CallPolicy.normalize(invoke.policy),
         {:ok, on_error} <- normalize_on_error(invoke.on_error),
         {:ok, targets, kinds} <- normalize_targets(invoke.targets),
         :ok <- validate_policy(policy, kinds) do
      {:ok,
       %__MODULE__{
         target: target,
         targets: targets,
         params: params,
         metadata: invoke.metadata,
         policy: policy,
         on_error: on_error
       }}
    end
  end

  def normalize(%{} = attrs) when not is_struct(attrs) do
    with {:ok, attrs} <- Validation.normalize_fields(attrs, @fields, "Invoke"),
         :ok <- Validation.validate_tag(attrs, :invoke, "Invoke"),
         {:ok, target} <- required(attrs, :target),
         {:ok, targets} <- required(attrs, :targets),
         {:ok, policy} <-
           CallPolicy.from_options(
             Map.get(attrs, :policy),
             Map.get(attrs, :timeout_ms),
             Map.get(attrs, :retry)
           ) do
      new(
        target,
        targets,
        Map.get(attrs, :params, %{}),
        Map.get(attrs, :meta, %{}),
        policy,
        Map.get(attrs, :on_error, :fail_fast)
      )
    end
  end

  def normalize(value) do
    {:error, Error.validation_error("Invoke form is invalid", %{reason: :invoke, value: value})}
  end

  @doc false
  @spec canonical?(term()) :: boolean()
  def canonical?(invoke) do
    case normalize(invoke) do
      {:ok, ^invoke} -> true
      _other -> false
    end
  end

  @doc false
  @spec allowed_ids(t()) :: [String.t()]
  def allowed_ids(%__MODULE__{targets: targets}), do: targets |> Map.keys() |> Enum.sort()

  defp required(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error,
         Error.validation_error("Invoke #{field} is required", %{
           reason: :invoke_required,
           field: field
         })}
    end
  end

  defp normalize_targets(targets) when is_map(targets) and not is_struct(targets) do
    if map_size(targets) == 0 do
      invalid_targets("Invoke targets cannot be empty", :empty_invoke_targets)
    else
      with :ok <- Limits.collection(targets, :targets) do
        targets
        |> Enum.sort_by(fn {id, _target} -> inspect(id) end)
        |> Enum.reduce_while({:ok, %{}, MapSet.new()}, fn {id, target}, {:ok, result, kinds} ->
          with :ok <- validate_id(id),
               {:ok, kind} <- validate_candidate(id, target) do
            {:cont, {:ok, Map.put(result, id, target), MapSet.put(kinds, kind)}}
          else
            {:error, error} -> {:halt, {:error, error}}
          end
        end)
      end
    end
  end

  defp normalize_targets(_targets),
    do: invalid_targets("Invoke targets must be a map", :invalid_invoke_targets)

  defp validate_id(id) when is_binary(id) and byte_size(id) > 0 do
    if String.valid?(id),
      do: :ok,
      else: invalid_targets("Invoke target ID must be valid UTF-8", :invalid_invoke_target_id)
  end

  defp validate_id(id) do
    invalid_targets("Invoke target ID must be a non-empty string", :invalid_invoke_target_id,
      target_id: id
    )
  end

  defp validate_candidate(id, target) when is_atom(target) do
    case Instruction.target_kind(target) do
      {:ok, :action} ->
        {:ok, :action}

      {:ok, :flow} ->
        if function_exported?(target, :flow, 0),
          do: {:ok, :flow},
          else: invalid_candidate(id, :missing_flow)

      {:error, cause} ->
        invalid_candidate(id, cause)
    end
  end

  defp validate_candidate(id, _target), do: invalid_candidate(id, :module_required)

  defp invalid_candidate(id, cause) do
    {:error,
     Error.validation_error("Invoke candidate must be an Action or Flow module", %{
       reason: :invalid_invoke_candidate,
       target_id: id,
       cause: cause
     })}
  end

  defp normalize_on_error(on_error) when on_error in [:fail_fast, :collect_errors],
    do: {:ok, on_error}

  defp normalize_on_error(on_error) do
    {:error,
     Error.validation_error("Invoke on_error policy is invalid", %{
       reason: :on_error,
       value: on_error
     })}
  end

  defp validate_policy(policy, _kinds) when map_size(policy) == 0, do: :ok

  defp validate_policy(_policy, kinds) do
    if MapSet.member?(kinds, :flow) do
      {:error,
       Error.validation_error("Flow call policy supports Action targets only", %{
         reason: :unsupported_flow_call_policy
       })}
    else
      :ok
    end
  end

  defp invalid_targets(message, reason, details \\ []) do
    {:error, Error.validation_error(message, Map.new([reason: reason] ++ details))}
  end
end
