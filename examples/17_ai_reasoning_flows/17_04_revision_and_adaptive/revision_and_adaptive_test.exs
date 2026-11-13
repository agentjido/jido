Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("../support/structured_reasoning_client.ex", __DIR__)
Code.require_file("revision_and_adaptive.ex", __DIR__)

defmodule Jido.Examples.AI.Reasoning.RevisionAndAdaptiveTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.Reasoning.{RevisionAndAdaptive, StructuredReasoningClient}

  test "TRM revises once while Adaptive selects an existing Flow" do
    assert {:ok, results} =
             Jido.Exec.run(
               RevisionAndAdaptive,
               %{input: "Return an evidence-based answer."},
               %{jido_ai_inference_client: StructuredReasoningClient}
             )

    revision = results.revision.response
    adaptive = results.adaptive.response

    assert revision.output == "revised answer"
    assert revision.model_calls == 3
    assert revision.reasoning.draft == "initial answer"
    assert revision.reasoning.critique == "add evidence"
    assert revision.reasoning.iterations == 1

    assert adaptive.output == "adaptive answer"
    assert adaptive.model_calls == 1
    assert adaptive.reasoning.method == :chain_of_draft
  end

  test "Adaptive also accepts an explicit trusted strategy name" do
    assert {:ok, %{response: response}} =
             Jido.Exec.run(
               Jido.AI.Reasoning.Adaptive,
               %{
                 input: "Use a short draft.",
                 strategy: :chain_of_draft,
                 model: "offline:adaptive",
                 options: %{offline_strategy: :adaptive}
               },
               %{jido_ai_inference_client: StructuredReasoningClient}
             )

    assert response.output == "adaptive answer"
    assert response.reasoning.method == :chain_of_draft
  end
end
