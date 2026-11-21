defmodule Jido.Examples.Evaluation.OfflineJudge.Judge do
  use Jido.Action, name: "example_evaluation_offline_judge"

  @impl true
  def run(%{case_id: case_id, state: state, questions: questions}, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)

    case client.evaluate("offline:judge", state, questions, []) do
      {:ok, response} ->
        {:ok,
         %{
           case_id: case_id,
           model: response.model,
           judge_output: ReqLLM.Response.text(response),
           recorded_input: %{state: state, questions: questions},
           input_digest: digest(%{state: state, questions: questions}),
           decision: :recorded
         }}

      {:error, reason} ->
        {:error, Jido.Error.execution_error("offline judge failed", %{reason: reason})}
    end
  end

  defp digest(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end

defmodule Jido.Examples.Evaluation.OfflineJudge do
  use Jido.Flow,
    name: "example_evaluation_offline_judge_flow",
    schema:
      Jido.Joi.object(%{
        case_id: Jido.Joi.string() |> Jido.Joi.min(1),
        state: Jido.Joi.map(),
        questions: Jido.Joi.map()
      })

  flow do
    step "judge",
      action: Jido.Examples.Evaluation.OfflineJudge.Judge,
      params: %{
        case_id: input(:case_id),
        state: input(:state),
        questions: input(:questions)
      }

    output result("judge")
  end
end
