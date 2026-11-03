defmodule Jido.Flow.Codec.Paths do
  @moduledoc false

  @type t :: %{optional(list()) => list()}

  @doc false
  @spec translate(list(), t()) :: list()
  def translate(path, paths) do
    Enum.find_value(length(path)..0//-1, fn size ->
      case Map.fetch(paths, Enum.take(path, size)) do
        {:ok, stored} -> stored ++ Enum.map(Enum.drop(path, size), &segment/1)
        :error -> nil
      end
    end) || Enum.map(path, &segment/1)
  end

  @doc false
  @spec error(Exception.t(), t()) :: Exception.t()
  def error(%{details: details} = error, paths) do
    {source, details} = Map.pop(details, :source_path)
    path = source || translate(Map.get(details, :path, []), paths)
    %{error | details: Map.put(details, :path, path)}
  end

  defp segment(value) when is_binary(value) or is_integer(value), do: value
  defp segment(value) when is_atom(value), do: Atom.to_string(value)
  defp segment(value), do: inspect(value)
end
