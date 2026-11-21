defmodule Jido.Examples.AI.Reasoning.BranchingComparison do
  @moduledoc "Runs Tree of Thoughts and Graph of Thoughts over one input."

  alias Jido.AI.Reasoning.{GraphOfThoughts, TreeOfThoughts}

  use Jido.Flow,
    name: "examples_ai_branching_reasoning_comparison",
    schema:
      Jido.Joi.object(
        %{input: Jido.Joi.string()},
        unrecognized_keys: :error
      )

  flow do
    step "tree",
      action: TreeOfThoughts,
      params: %{
        input: input(:input),
        model: "offline:tree",
        options: %{offline_strategy: :tree}
      }

    step "graph",
      action: GraphOfThoughts,
      params: %{
        input: input(:input),
        model: "offline:graph",
        options: %{offline_strategy: :graph}
      }

    output %{tree: result("tree"), graph: result("graph")}
  end
end
