defmodule Jido.Examples.AI.CoreComposition.Audit do
  @moduledoc "A second stateless Agent Plugin."

  use Jido.Plugin, id: "examples.audit"

  @impl Jido.Plugin
  def prepare(_preparation, _options), do: {:ok, :audited}
end

defmodule Jido.Examples.AI.CoreComposition.Agent do
  @moduledoc "A graph-first AI Agent with one application Plugin."

  use Jido.AI.Agent,
    name: "core_composition_example",
    plugins: [Jido.Examples.AI.CoreComposition.Audit]

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer a customer question."
    end
  end
end
