defmodule Jido.Exec.Source do
  @moduledoc false

  @doc false
  @spec attach(term(), map() | nil, map()) :: term()
  def attach(error, location, extra \\ %{})

  def attach(%{details: details} = error, location, extra) when is_map(details) do
    source_details =
      extra
      |> maybe_put(:source, location)

    %{error | details: Map.merge(details, source_details)}
  end

  def attach(error, _location, _extra), do: error

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
