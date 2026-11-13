Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("../support/structured_reasoning_client.ex", __DIR__)
Code.require_file("branching_reasoning_comparison.ex", __DIR__)

defmodule Jido.Examples.AI.Reasoning.BranchingComparisonTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.Reasoning.{BranchingComparison, StructuredReasoningClient}

  test "tree and graph strategies preserve different intermediate structures" do
    assert {:ok, results} =
             Jido.Exec.run(
               BranchingComparison,
               %{input: "Compare ways to prepare a release."},
               %{jido_ai_inference_client: StructuredReasoningClient}
             )

    tree = results.tree.response
    graph = results.graph.response

    assert tree.output == "selected answer"
    assert tree.model_calls == 3
    assert Enum.map(tree.reasoning.thoughts, & &1.score) == [0.1, 0.9, 0.6]

    assert graph.output == "graph answer"
    assert graph.model_calls == 2
    assert Enum.map(graph.reasoning.nodes, & &1.id) == ["facts", "answer"]
    assert graph.reasoning.edges == [%{from: "facts", to: "answer", relationship: "supports"}]
  end
end
