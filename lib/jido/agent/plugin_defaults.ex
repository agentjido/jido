defmodule Jido.Agent.PluginDefaults do
  @moduledoc "The canonical host-default plugin policy in an Agent definition."

  alias Jido.Agent.Plugin
  alias Jido.Error

  @type mode :: :inherit | :none
  @type state_key :: atom()
  @type override :: :disabled | Plugin.t()
  @type t :: %__MODULE__{mode: mode(), overrides: %{optional(state_key()) => override()}}

  defstruct mode: :inherit, overrides: %{}

  @doc "Builds and validates one canonical default-plugin policy."
  @spec new(map() | keyword() | mode() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = defaults), do: defaults |> Map.from_struct() |> new()
  def new(mode) when mode in [:inherit, :none], do: {:ok, %__MODULE__{mode: mode}}

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid_map()
  end

  def new(%{} = attrs) do
    with :ok <- known_keys(attrs),
         {:ok, mode} <- mode(Map.get(attrs, :mode, :inherit)),
         {:ok, overrides} <- overrides(Map.get(attrs, :overrides, %{})) do
      {:ok, %__MODULE__{mode: mode, overrides: overrides}}
    end
  end

  def new(_attrs), do: invalid_map()

  @doc "Builds one canonical default-plugin policy or raises its validation error."
  @spec new!(map() | keyword() | mode() | t()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, defaults} -> defaults
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = defaults) do
    %{
      mode: defaults.mode,
      overrides:
        Map.new(defaults.overrides, fn
          {key, :disabled} -> {key, :disabled}
          {key, %Plugin{} = plugin} -> {key, Plugin.to_map(plugin)}
        end)
    }
  end

  defp known_keys(attrs) do
    case Enum.find(Map.keys(attrs), &(&1 not in [:mode, :overrides])) do
      nil -> :ok
      key -> {:error, error("unknown plugin-default key: #{inspect(key)}", %{key: key})}
    end
  end

  defp mode(value) when value in [:inherit, :none], do: {:ok, value}
  defp mode(_value), do: {:error, error("plugin-default mode must be :inherit or :none")}

  defp overrides(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.reduce_while({:ok, %{}}, fn {key, declaration}, {:ok, acc} ->
      with :ok <- state_key(key),
           {:ok, declaration} <- override(declaration) do
        {:cont, {:ok, Map.put(acc, key, declaration)}}
      else
        {:error, validation_error} ->
          {:halt, {:error, prefix(validation_error, [:overrides, key])}}
      end
    end)
  end

  defp overrides(_value), do: {:error, error("plugin-default overrides must be a map")}

  defp state_key(key) when is_atom(key) and key not in [nil, true, false], do: :ok
  defp state_key(_key), do: {:error, error("plugin-default state keys must be atoms")}

  defp override(:disabled), do: {:ok, :disabled}
  defp override(value), do: Plugin.new(value)

  defp invalid_map, do: {:error, error("plugin-default configuration must be a map")}

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp prefix(%{details: details} = validation_error, path) when is_map(details),
    do: %{
      validation_error
      | details: Map.put(details, :path, path ++ Map.get(details, :path, []))
    }
end
