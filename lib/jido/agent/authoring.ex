defmodule Jido.Agent.Authoring do
  @moduledoc false

  alias Jido.Error

  def attrs(value) do
    case to_attrs(value, :reject) do
      {:ok, attrs} -> {:ok, attrs}
      :error when is_list(value) -> error("Expected unique keyword options", %{value: value})
      :error -> error("Expected a map or keyword list", %{value: value})
    end
  end

  # Public boundaries keep their own duplicate policy and error context.
  def to_attrs(value, duplicates \\ :last)
  def to_attrs(value, _duplicates) when is_map(value) and not is_struct(value), do: {:ok, value}

  def to_attrs(value, duplicates) when is_list(value) do
    if Keyword.keyword?(value) and
         (duplicates == :last or Enum.uniq(Keyword.keys(value)) == Keyword.keys(value)),
       do: {:ok, Map.new(value)},
       else: :error
  end

  def to_attrs(_value, _duplicates), do: :error

  def keys(map, allowed) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      unknown -> error("Unknown authoring fields", %{keys: unknown})
    end
  end

  def traverse(values, fun), do: traverse(values, fun, [])
  defp traverse([], _fun, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | tail], fun, acc) do
    case fun.(value) do
      {:ok, result} -> traverse(tail, fun, [result | acc])
      {:error, _error} = error -> error
    end
  end

  defp traverse(_tail, _fun, _acc), do: error("Expected a proper list")

  def error(message, details \\ %{}),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}
end
