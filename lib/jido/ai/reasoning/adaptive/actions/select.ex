defmodule Jido.AI.Reasoning.Adaptive.Actions.Select do
  @moduledoc "Selects one reasoning Flow from request text or an explicit override."
  use Jido.Action,
    id: "jido.ai/reasoning/adaptive/actions/select",
    vsn: 1,
    name: "jido_ai_adaptive_select",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @tool ~w(search find lookup fetch calculate compute execute run tool)
  @synthesis ~w(synthesize combine merge integrate relationships perspectives)
  @explore ~w(analyze explore compare evaluate alternatives options)
  @recursive ~w(puzzle riddle iterate improve refine recursive)
  @algorithm ~w(algorithm backtrack search-space optimize)

  @impl Jido.Action
  def run(params, _context) do
    strategy = Map.get(params, :strategy) || select(text(params.input))
    {:ok, %{strategy: strategy, input: Map.delete(params, :strategy)}}
  end

  defp select(text) do
    words = text |> String.downcase() |> String.split(~r/[^a-z0-9-]+/, trim: true)

    cond do
      any?(words, @recursive) -> :trm
      any?(words, @synthesis) -> :graph_of_thoughts
      any?(words, @tool) -> :react
      any?(words, @algorithm) -> :algorithm_of_thoughts
      any?(words, @explore) -> :tree_of_thoughts
      length(words) < 12 -> :chain_of_draft
      true -> :chain_of_thought
    end
  end

  defp any?(words, candidates), do: Enum.any?(candidates, &(&1 in words))

  defp text(input) when is_binary(input), do: input

  defp text(parts) when is_list(parts) do
    Enum.map_join(parts, " ", fn part -> Map.get(part, :text, Map.get(part, "text", "")) end)
  end
end
