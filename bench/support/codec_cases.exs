defmodule JidoCoreBench.CodecCases do
  @moduledoc false
  alias Jido.Agent.Codec.Data
  alias JidoCoreBench.Fixtures, as: F

  def workloads do
    for size <- [0, 8, 1_000, 10_000], shape <- [:scalar, :nested, :bad_key, :bad_value] do
      F.checked(
        "codec/check_map/#{size}/#{shape}",
        fn _ -> document(size, shape) end,
        &Data.check_document/1,
        &check(&1, shape)
      )
    end
  end

  defp document(size, shape) do
    value =
      Map.new(1..size//1, fn n ->
        item = if shape == :nested, do: %{"items" => [n, "text", true]}, else: n
        {"key-#{n}", item}
      end)

    case shape do
      :bad_key -> value |> Map.delete("key-1") |> Map.put(:invalid, self())
      :bad_value -> Map.put(value, "key-1", self())
      _ -> value
    end
  end

  defp check(:ok, shape) when shape in [:scalar, :nested], do: :ok

  defp check({:error, %Jido.Error.ValidationError{message: message}}, shape) do
    expected =
      case shape do
        :bad_key -> "Document object keys must be strings"
        :bad_value -> "Invalid or oversized JSON document value"
      end

    F.equal!(message, expected)
  end
end
