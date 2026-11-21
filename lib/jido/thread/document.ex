defmodule Jido.Thread.Document do
  @moduledoc false

  def aliases(fields) do
    Map.new(for key <- fields, name <- [key, Atom.to_string(key)], do: {name, key})
  end

  def normalize_fields(map, aliases) do
    Enum.reduce_while(Map.to_list(map), {:ok, %{}}, fn {name, value}, {:ok, fields} ->
      with {:ok, key} <- Map.fetch(aliases, name),
           false <- Map.has_key?(fields, key) do
        {:cont, {:ok, Map.put(fields, key, value)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  def field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  def default(nil, fallback), do: fallback
  def default(value, _fallback), do: value
end
