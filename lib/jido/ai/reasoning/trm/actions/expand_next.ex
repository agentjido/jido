defmodule Jido.AI.Reasoning.TRM.Actions.ExpandNext do
  @moduledoc "Continues the bounded TRM cycle or returns its result."

  alias Jido.AI.Reasoning.TRM.ModelRound

  use Jido.Action,
    id: "jido.ai/reasoning/trm/actions/expand-next",
    vsn: 1,
    name: "jido_ai_trm_expand_next",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}
  def run(%{kind: :model, input: input}, _context), do: {:continue, input, ModelRound}
end
