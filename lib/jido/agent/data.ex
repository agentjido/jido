defmodule Jido.Agent.Data do
  @moduledoc """
  Validates portable literal and metadata data in an Agent definition.

  Agent data contains JSON scalar values, existing atoms, named MFA tuples,
  proper lists, and Maps with supported keys. All strings must contain valid
  UTF-8 data.
  """

  alias Jido.Error

  @type scalar :: nil | boolean() | number() | String.t() | atom()
  @type key :: String.t() | non_neg_integer() | atom()
  @type named_mfa :: {module(), atom(), [t()]}
  @type t :: scalar() | named_mfa() | [t()] | %{optional(key()) => t()}
  @type object :: %{optional(key()) => t()}

  @doc "Validates portable Agent data."
  @spec validate(term()) :: :ok | {:error, Error.ValidationError.t()}
  def validate(value), do: validate(value, [])

  @doc "Validates a portable Agent data Map."
  @spec validate_object(term()) :: :ok | {:error, Error.ValidationError.t()}
  def validate_object(value) when is_map(value) and not is_struct(value), do: validate(value)

  def validate_object(_value) do
    {:error, error("agent metadata must be a portable map")}
  end

  @doc false
  @spec validate_key(term()) :: :ok | {:error, Error.ValidationError.t()}
  def validate_key(key), do: validate_key(key, [])

  defp validate(value, _path)
       when is_nil(value) or is_boolean(value) or is_integer(value) or is_float(value) or
              is_atom(value),
       do: :ok

  defp validate(value, path) when is_binary(value) do
    if String.valid?(value),
      do: :ok,
      else: {:error, error("agent data strings must be valid UTF-8", %{path: path})}
  end

  defp validate({module, function, arguments}, path)
       when is_atom(module) and not is_nil(module) and is_atom(function) and
              not is_nil(function) and is_list(arguments) do
    validate(arguments, path ++ [2])
  end

  defp validate(value, path) when is_list(value) do
    if List.improper?(value) do
      {:error, error("agent data must contain proper lists", %{path: path})}
    else
      value
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
        case validate(item, path ++ [index]) do
          :ok -> {:cont, :ok}
          {:error, validation_error} -> {:halt, {:error, validation_error}}
        end
      end)
    end
  end

  defp validate(value, path) when is_map(value) and not is_struct(value) do
    value
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _item} -> :erlang.term_to_binary(key, [:deterministic]) end)
    |> Enum.reduce_while(:ok, fn {key, item}, :ok ->
      with :ok <- validate_key(key, path),
           :ok <- validate(item, path ++ [key]) do
        {:cont, :ok}
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp validate(value, path) do
    {:error,
     error("agent data contains an unsupported value", %{
       path: path,
       value_type: value_type(value)
     })}
  end

  defp validate_key(key, path) when is_binary(key), do: validate(key, path)

  defp validate_key(key, _path)
       when (is_integer(key) and key >= 0) or (is_atom(key) and not is_nil(key)),
       do: :ok

  defp validate_key(key, path) do
    {:error,
     error("agent data contains an unsupported map key", %{
       path: path,
       key: key
     })}
  end

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp value_type(value) when is_tuple(value), do: :tuple
  defp value_type(value) when is_function(value), do: :function
  defp value_type(value) when is_pid(value), do: :pid
  defp value_type(value) when is_port(value), do: :port
  defp value_type(value) when is_reference(value), do: :reference
  defp value_type(%{__struct__: module}), do: {:struct, module}
  defp value_type(_value), do: :other
end
