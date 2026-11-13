Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("offline_model_judge.ex", __DIR__)

defmodule Jido.Examples.Evaluation.OfflineJudgeTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Evaluation.OfflineJudge
  alias Jido.Examples.Support.OfflineInferenceClient

  @input %{
    case_id: "judge-citation-1",
    state: %{answer: "The limit is 30 days [doc-1].", source: %{id: "doc-1", revision: 3}},
    questions: %{
      citation_supported: "Does the answer cite the supplied source?",
      concise: "Is the answer concise?"
    }
  }

  test "records judge input, output, model, and digest" do
    context = %{jido_ai_inference_client: OfflineInferenceClient}
    assert {:ok, first} = Jido.Exec.run(OfflineJudge, @input, context)
    assert {:ok, second} = Jido.Exec.run(OfflineJudge, @input, context)

    assert first == second
    assert first.model == "offline:judge"
    assert first.judge_output == "offline judge: 2 checks"
    assert first.recorded_input == %{state: @input.state, questions: @input.questions}
    assert first.decision == :recorded
  end
end
