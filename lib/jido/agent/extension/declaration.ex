defmodule Jido.Agent.Extension.Declaration do
  @moduledoc "A canonical typed Agent extension declaration."

  alias Jido.Agent.Data
  alias Jido.Error

  @type t :: %__MODULE__{module: module(), data: term(), metadata: Data.object()}

  defstruct module: nil, data: %{}, metadata: %{}

  @doc "Builds and validates one canonical extension declaration."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = declaration), do: declaration |> Map.from_struct() |> new()

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid_map()
  end

  def new(%{} = attrs) do
    with :ok <- known_keys(attrs),
         {:ok, module} <- module(Map.get(attrs, :module)),
         {:ok, data} <- static_data(Map.get(attrs, :data, %{})),
         {:ok, metadata} <- metadata(Map.get(attrs, :metadata, %{})) do
      {:ok, %__MODULE__{module: module, data: data, metadata: metadata}}
    end
  end

  def new(_attrs), do: invalid_map()

  @doc "Builds one canonical extension declaration or raises its validation error."
  @spec new!(map() | keyword() | t()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, declaration} -> declaration
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = declaration) do
    %{module: declaration.module, data: declaration.data, metadata: declaration.metadata}
  end

  defp known_keys(attrs) do
    case Enum.find(Map.keys(attrs), &(&1 not in [:module, :data, :metadata])) do
      nil -> :ok
      key -> {:error, error("unknown Agent extension key: #{inspect(key)}", %{key: key})}
    end
  end

  defp module(value) when is_atom(value) and value not in [nil, true, false], do: {:ok, value}
  defp module(_value), do: {:error, error("agent extension module must be a module atom")}

  defp static_data(value) do
    case Jido.Action.validate_static_data(value) do
      :ok ->
        {:ok, value}

      {:error, reason} ->
        {:error, error("agent extension data must be static module data; #{reason}")}
    end
  end

  defp metadata(value) do
    case Data.validate_object(value) do
      :ok -> {:ok, value}
      {:error, validation_error} -> {:error, prefix(validation_error, [:metadata])}
    end
  end

  defp invalid_map, do: {:error, error("agent extension configuration must be a map")}

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp prefix(%{details: details} = validation_error, path) when is_map(details),
    do: %{
      validation_error
      | details: Map.put(details, :path, path ++ Map.get(details, :path, []))
    }
end
