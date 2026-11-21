defmodule Jido.Test.Property.Signal.Model do
  @moduledoc false

  # A recursive language recognizer. It does not call the trie or compiled matcher.
  def matches?(type, path), do: segments(String.split(type, "."), String.split(path, "."))
  defp segments([], []), do: true
  defp segments(type, ["**" | rest]), do: segments(type, rest) or consume(type, ["**" | rest])
  defp segments([_ | tail], ["*" | rest]), do: segments(tail, rest)
  defp segments([same | tail], [same | rest]), do: segments(tail, rest)
  defp segments(_, _), do: false
  defp consume([_ | tail], pattern), do: segments(tail, pattern)
  defp consume([], _), do: false

  def record(cursor, type) do
    %{
      "format_version" => 1,
      "id" => "record-#{cursor}",
      "cursor" => cursor,
      "type" => type,
      "created_at" => "2026-09-29T00:00:00Z",
      "signal" => %{
        "specversion" => "1.0",
        "id" => "signal-#{cursor}",
        "source" => "/p",
        "type" => type
      }
    }
  end

  def definition(id, path, cursor) do
    %{
      "format_version" => 1,
      "id" => id,
      "path" => path,
      "cursor" => cursor,
      "created_at" => "2026-09-29T00:00:00Z"
    }
  end
end
