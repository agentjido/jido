Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("linear_reasoning_comparison.ex", __DIR__)

defmodule Jido.Examples.AI.Reasoning.LinearComparisonTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.Reasoning.LinearComparison
  alias Jido.Examples.Support.OfflineInferenceClient

  test "three linear strategies expose different reasoning data for one answer" do
    assert {:ok, results} =
             Jido.Exec.run(
               LinearComparison,
               %{input: "What is 19 plus 23?"},
               %{jido_ai_inference_client: OfflineInferenceClient}
             )

    chain = results.chain_of_thought.response
    draft = results.chain_of_draft.response
    algorithm = results.algorithm_of_thoughts.response

    assert chain.output == "42"
    assert draft.output == "42"
    assert algorithm.output == "42"

    assert chain.reasoning.method == :chain_of_thought
    assert length(chain.reasoning.steps) == 2

    assert %{
             method: :chain_of_draft,
             drafts: ["identify values", "add values"],
             conclusion: "42",
             steps_count: 2
           } = draft.reasoning

    assert %{
             method: :algorithm_of_thoughts,
             operations: ["select addition", "apply addition", "verify result"],
             conclusion: "42",
             steps_count: 3
           } = algorithm.reasoning

    assert Enum.all?([chain, draft, algorithm], &(&1.model_calls == 1))
  end

  test "the outer comparison is a normal Flow with three bounded Flow calls" do
    assert %Jido.Flow{components: components} = LinearComparison.flow()

    assert Enum.all?(
             ["chain_of_thought", "chain_of_draft", "algorithm_of_thoughts"],
             &(components[&1].kind == :call)
           )
  end
end
