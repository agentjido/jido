defmodule Jido.Flow.Form.Validation do
  @moduledoc false

  alias Jido.Flow.{Call, Error}

  @doc false
  @spec normalize_call(term(), Jido.Flow.Ref.scope(), String.t()) ::
          {:ok, Call.t()} | {:error, Exception.t()}
  defdelegate normalize_call(value, scope, label), to: Call, as: :normalize

  @doc false
  @spec normalize_fields(map(), [atom()], String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def normalize_fields(attrs, fields, label) do
    attrs
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      normalized_key =
        if is_binary(key), do: Enum.find(fields, &(Atom.to_string(&1) == key)), else: key

      cond do
        normalized_key not in fields ->
          {:halt,
           {:error,
            Error.validation_error("#{label} form contains an unknown field", %{
              reason: :unknown_field,
              field: key
            })}}

        Map.has_key?(normalized, normalized_key) ->
          {:halt,
           {:error,
            Error.validation_error("#{label} form contains a duplicate field", %{
              reason: :duplicate_field,
              field: normalized_key
            })}}

        true ->
          {:cont, {:ok, Map.put(normalized, normalized_key, value)}}
      end
    end)
  end

  @doc false
  @spec validate_tag(map(), atom(), String.t()) :: :ok | {:error, Exception.t()}
  def validate_tag(attrs, expected_type, label) do
    type = Map.get(attrs, :type, expected_type)

    if type in [expected_type, Atom.to_string(expected_type)] do
      :ok
    else
      {:error,
       Error.validation_error("#{label} form type is invalid", %{reason: :form, type: type})}
    end
  end

  @doc false
  @spec collection(map(), String.t()) :: {:ok, term()} | {:error, Exception.t()}
  def collection(%{collection: value}, _label), do: {:ok, value}

  def collection(_attrs, label) do
    {:error,
     Error.validation_error("#{label} collection is required", %{reason: :collection_required})}
  end

  @doc false
  @spec call(map(), String.t()) :: {:ok, term()} | {:error, Exception.t()}
  def call(%{call: call} = attrs, label) do
    if Enum.any?(
         [:action, :params, :context, :metadata, :policy, :timeout_ms, :retry],
         &Map.has_key?(attrs, &1)
       ) do
      {:error,
       Error.validation_error("#{label} call cannot be mixed with Action fields", %{reason: :call})}
    else
      {:ok, call}
    end
  end

  def call(%{action: action} = attrs, _label) do
    {:ok,
     %{
       type: :call,
       action: action,
       params: Map.get(attrs, :params, %{}),
       context: Map.get(attrs, :context, %{}),
       metadata: Map.get(attrs, :metadata, %{}),
       policy: Map.get(attrs, :policy),
       timeout_ms: Map.get(attrs, :timeout_ms),
       retry: Map.get(attrs, :retry)
     }}
  end

  def call(_attrs, label) do
    {:error,
     Error.validation_error("#{label} Action or call is required", %{reason: :call_required})}
  end

  @doc false
  @spec validate_on_error(term(), String.t()) :: :ok | {:error, Exception.t()}
  def validate_on_error(policy, _label) when policy in [:fail_fast, :collect_errors], do: :ok

  def validate_on_error(policy, label) do
    {:error,
     Error.validation_error("#{label} on_error policy is invalid", %{
       reason: :on_error,
       value: policy
     })}
  end

  @doc false
  @spec require_fail_fast(Call.t(), String.t()) ::
          {:ok, Call.t()} | {:error, Exception.t()}
  def require_fail_fast(%Call{on_error: :fail_fast} = call, _label), do: {:ok, call}

  def require_fail_fast(%Call{on_error: on_error}, label) do
    {:error,
     Error.validation_error("#{label} must use fail-fast error handling", %{
       reason: :nested_on_error,
       on_error: on_error
     })}
  end

  @doc false
  @spec normalize_name(term(), String.t(), atom(), list()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def normalize_name(name, label, reason, path)

  def normalize_name(name, label, reason, path)
      when is_atom(name) and name not in [nil, true, false],
      do: normalize_name(Atom.to_string(name), label, reason, path)

  def normalize_name(name, label, reason, path) when is_binary(name) do
    case Jido.Authoring.Config.validate_name(name, subject: label) do
      :ok ->
        {:ok, name}

      {:error, message} ->
        {:error, Error.validation_error(message, %{reason: reason, path: path})}
    end
  end

  def normalize_name(_name, label, reason, path) do
    {:error,
     Error.validation_error("#{label} name must be a string or atom", %{
       reason: reason,
       path: path
     })}
  end
end
