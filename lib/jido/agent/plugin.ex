defmodule Jido.Agent.Plugin do
  @moduledoc "A canonical Agent plugin declaration."

  alias Jido.Agent.Data
  alias Jido.Error

  @type t :: %__MODULE__{
          module: module(),
          as: atom() | nil,
          config: Data.object(),
          metadata: Data.object()
        }

  defstruct module: nil, as: nil, config: %{}, metadata: %{}

  @doc "Builds and validates one canonical plugin declaration."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = plugin), do: plugin |> Map.from_struct() |> new()

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid_map()
  end

  def new(%{} = attrs) do
    with :ok <- known_keys(attrs),
         {:ok, module} <- module(Map.get(attrs, :module)),
         {:ok, as} <- alias_name(Map.get(attrs, :as)),
         {:ok, config} <- object(Map.get(attrs, :config, %{}), :config),
         {:ok, metadata} <- object(Map.get(attrs, :metadata, %{}), :metadata) do
      {:ok, %__MODULE__{module: module, as: as, config: config, metadata: metadata}}
    end
  end

  def new(_attrs), do: invalid_map()

  @doc "Builds one canonical plugin declaration or raises its validation error."
  @spec new!(map() | keyword() | t()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, plugin} -> plugin
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = plugin) do
    %{
      module: plugin.module,
      as: plugin.as,
      config: plugin.config,
      metadata: plugin.metadata
    }
  end

  defp known_keys(attrs) do
    case Enum.find(Map.keys(attrs), &(&1 not in [:module, :as, :config, :metadata])) do
      nil -> :ok
      key -> {:error, error("unknown Agent plugin key: #{inspect(key)}", %{key: key})}
    end
  end

  defp module(value) when is_atom(value) and value not in [nil, true, false], do: {:ok, value}
  defp module(_value), do: {:error, error("agent plugin module must be a module atom")}

  defp alias_name(nil), do: {:ok, nil}
  defp alias_name(value) when is_atom(value) and value not in [true, false], do: {:ok, value}
  defp alias_name(_value), do: {:error, error("agent plugin alias must be an atom")}

  defp object(value, field) do
    case Data.validate_object(value) do
      :ok -> {:ok, value}
      {:error, validation_error} -> {:error, prefix(validation_error, [field])}
    end
  end

  defp invalid_map, do: {:error, error("agent plugin configuration must be a map")}

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp prefix(%{details: details} = validation_error, path) when is_map(details),
    do: %{
      validation_error
      | details: Map.put(details, :path, path ++ Map.get(details, :path, []))
    }
end
