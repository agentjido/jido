defmodule JidoCoreBench.CodecCases do
  @moduledoc false
  alias Jido.Authoring.Document
  alias JidoCoreBench.Fixtures, as: F

  def workloads do
    for size <- [0, 8, 1_000, 10_000], shape <- [:scalar, :nested, :deep, :improper] do
      F.checked(
        "codec/check_map/#{size}/#{shape}",
        fn _ -> document(size, shape) end,
        &Document.check/1,
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
      :deep -> Enum.reduce(1..102, 0, fn _index, item -> [item] end)
      :improper -> [value | :tail]
      _shape -> value
    end
  end

  defp check(:ok, shape) when shape in [:scalar, :nested], do: :ok

  defp check({:error, %Jido.Authoring.Document.Error{reason: reason}}, shape) do
    expected = if shape == :deep, do: :depth, else: :collection
    F.equal!(reason, expected)
  end
end
