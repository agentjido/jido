Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("two_step_rag.ex", __DIR__)

defmodule Jido.Examples.RAG.TwoStepTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.RAG.TwoStep
  alias Jido.Examples.Support.OfflineInferenceClient

  @documents [
    %{id: "doc-1", revision: 3, text: "The policy limit is 30 days for report retention."},
    %{id: "doc-2", revision: 1, text: "Accounts use two-factor authentication."}
  ]

  test "retrieves, reranks, generates, cites, and checks one offline answer" do
    assert {:ok, result} =
             Jido.Exec.run(
               TwoStep,
               %{query: "What is the report retention policy limit?", documents: @documents, top_k: 2},
               %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert result.answer == "The policy limit is 30 days [doc-1]."
    assert result.citations == [%{id: "doc-1", revision: 3}]
    assert result.quality == %{citation_present: true, passed: true}
    assert [%{id: "doc-1", retrieval_score: score, rerank_score: 1.0}] = result.retrieved
    assert score > 0
  end

  test "an empty retrieval stops before generation" do
    assert {:error, %Jido.Error.ValidationError{details: %{boundary: :retrieval_quality}}} =
             Jido.Exec.run(
               TwoStep,
               %{query: "unrelated zebras", documents: @documents, top_k: 2},
               %{jido_ai_inference_client: OfflineInferenceClient}
             )
  end
end
