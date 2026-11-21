defmodule Jido.Examples.AI.Reasoning.LinearComparison do
  @moduledoc "Runs three one-call structured reasoning Flows over the same input."

  alias Jido.AI.Reasoning.{AlgorithmOfThoughts, ChainOfDraft, ChainOfThought}

  use Jido.Flow,
    name: "examples_ai_linear_reasoning_comparison",
    schema:
      Jido.Joi.object(
        %{input: Jido.Joi.string()},
        unrecognized_keys: :error
      )

  flow do
    step "chain_of_thought",
      action: ChainOfThought,
      params: %{
        input: input(:input),
        model: "offline:chain-of-thought",
        options: %{
          offline_object: %{
            "steps" => [
              %{"number" => 1, "content" => "identify the values"},
              %{"number" => 2, "content" => "add the values"}
            ],
            "conclusion" => "42"
          }
        }
      }

    step "chain_of_draft",
      action: ChainOfDraft,
      params: %{
        input: input(:input),
        model: "offline:chain-of-draft",
        options: %{
          offline_object: %{
            "drafts" => ["identify values", "add values"],
            "answer" => "42"
          }
        }
      }

    step "algorithm_of_thoughts",
      action: AlgorithmOfThoughts,
      params: %{
        input: input(:input),
        model: "offline:algorithm-of-thoughts",
        options: %{
          offline_object: %{
            "operations" => ["select addition", "apply addition", "verify result"],
            "answer" => "42"
          }
        }
      }

    output %{
      chain_of_thought: result("chain_of_thought"),
      chain_of_draft: result("chain_of_draft"),
      algorithm_of_thoughts: result("algorithm_of_thoughts")
    }
  end
end
