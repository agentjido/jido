defmodule JidoCoreBench.MergeCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F

  def workloads do
    cases =
      for count <- [8, 128, 1_024], mode <- [:empty, :append, :replace_last, :non_keyword] do
        left = for i <- 1..count, do: {String.to_atom("bench_merge_#{i}"), %{left: i}}
        {last, _} = List.last(left)

        {right, expected} =
          case mode do
            :empty ->
              {[], left}

            :append ->
              {[extra: 1], left ++ [extra: 1]}

            :replace_last ->
              {[{last, %{right: count}}],
               Enum.drop(left, -1) ++ [{last, %{left: count, right: count}}]}

            :non_keyword ->
              {[{"item", 1}], [{"item", 1}]}
          end

        batch("state/merge_keywords/#{count}/#{mode}/25", left, right, expected)
      end

    cases ++
      [
        batch(
          "state/merge_keywords/duplicates/25",
          [config: [item: 1, item: 2]],
          [config: [extra: 3]], config: [item: 1, item: 2, extra: 3])
      ]
  end

  defp batch(id, left, right, expected) do
    F.checked(
      id,
      fn _ -> {left, right} end,
      fn {a, b} -> for _ <- 1..25, do: Jido.Util.DeepMerge.merge(a, b) end,
      fn results ->
        F.equal!(length(results), 25)
        Enum.each(results, &F.equal!(&1, expected))
        :ok
      end
    )
  end
end
