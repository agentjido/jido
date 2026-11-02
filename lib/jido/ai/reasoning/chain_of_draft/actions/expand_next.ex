defmodule Jido.AI.Reasoning.ChainOfDraft.Actions.ExpandNext do
  @moduledoc "Expands the trusted Chain of Draft routing decision."

  alias Jido.AI.Reasoning.ChainOfDraft.ModelRound

  use Jido.Action,
    id: "jido.ai/reasoning/chain-of-draft/actions/expand-next",
    vsn: 1,
    name: "jido_ai_chain_of_draft_expand_next",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}
  def run(%{kind: :model, input: input}, _context), do: {:continue, input, ModelRound}
end
