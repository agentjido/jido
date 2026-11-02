defmodule Jido.Signal.Context do
  @moduledoc """
  Validates CloudEvents extension context attributes.

  Extension attributes are flat transport metadata. Domain data belongs in the
  Signal `data` field and can be validated by a custom Signal module.
  """

  alias Jido.Signal

  @core_names ~w[
    specversion id source type subject time
    datacontenttype dataschema data data_base64
  ]
  @name_pattern ~r/\A[a-z][a-z0-9]{0,19}\z/
  @min_integer -2_147_483_648
  @max_integer 2_147_483_647

  @type name :: String.t()
  @type int32 :: -2_147_483_648..2_147_483_647
  @type value :: boolean() | int32() | binary()
  @type t :: %{optional(name()) => value()}

  @doc "Validates and normalizes a context attribute map."
  @spec normalize(map()) :: {:ok, t()} | {:error, String.t()}
  def normalize(attributes) when is_map(attributes) do
    Enum.reduce_while(Map.to_list(attributes), {:ok, %{}}, fn {name, value}, {:ok, acc} ->
      with {:ok, name} <- normalize_name(name),
           :ok <- validate_value(value) do
        if Map.has_key?(acc, name) do
          {:halt, {:error, "duplicate extension attribute #{inspect(name)}"}}
        else
          {:cont, {:ok, Map.put(acc, name, value)}}
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def normalize(_attributes), do: {:error, "extensions must be a map"}

  @doc "Adds one validated context attribute to a Signal."
  @spec put(Signal.t(), atom() | String.t(), value()) ::
          {:ok, Signal.t()} | {:error, String.t()}
  def put(%Signal{} = signal, name, value) do
    with {:ok, name} <- normalize_name(name),
         :ok <- validate_value(value) do
      {:ok, %{signal | extensions: Map.put(signal.extensions, name, value)}}
    end
  end

  def put(_signal, _name, _value), do: {:error, "expected a Signal struct"}

  @doc "Gets one context attribute from a Signal."
  @spec get(Signal.t(), atom() | String.t()) :: value() | nil
  def get(%Signal{} = signal, name) when is_atom(name) or is_binary(name) do
    Map.get(signal.extensions, to_string(name))
  end

  def get(_signal, _name), do: nil

  @doc "Deletes one context attribute from a Signal."
  @spec delete(Signal.t(), atom() | String.t()) :: Signal.t()
  def delete(%Signal{} = signal, name) when is_atom(name) or is_binary(name) do
    %{signal | extensions: Map.delete(signal.extensions, to_string(name))}
  end

  def delete(signal, _name), do: signal

  @doc "Lists the context attribute names on a Signal."
  @spec names(Signal.t()) :: [name()]
  def names(%Signal{} = signal), do: Map.keys(signal.extensions)
  def names(_signal), do: []

  @doc false
  @spec normalize_name(term()) :: {:ok, name()} | {:error, String.t()}
  def normalize_name(name) when is_atom(name), do: normalize_name(Atom.to_string(name))

  def normalize_name(name) when is_binary(name) do
    cond do
      name in @core_names ->
        {:error, "extension name #{inspect(name)} conflicts with a CloudEvents attribute"}

      Regex.match?(@name_pattern, name) ->
        {:ok, name}

      true ->
        {:error,
         "extension name #{inspect(name)} must start with a lower-case letter, contain only lower-case letters and digits, and have at most 20 characters"}
    end
  end

  def normalize_name(name), do: {:error, "invalid extension name #{inspect(name)}"}

  defp validate_value(value) when is_boolean(value), do: :ok

  defp validate_value(value)
       when is_integer(value) and value >= @min_integer and value <= @max_integer,
       do: :ok

  defp validate_value(value) when is_binary(value), do: :ok

  defp validate_value(value) do
    {:error,
     "extension values must be a Boolean, signed 32-bit Integer, String, Binary, URI, URI-reference, or Timestamp; got: #{inspect(value)}"}
  end
end
