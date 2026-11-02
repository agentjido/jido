defmodule Jido.AI.Reasoning.ChainOfDraft.ModelRound do
  @moduledoc "Runs one structured Chain of Draft model response."

  alias Jido.AI.Reasoning.Actions.{CallModel, GuardOutput, ProjectConversation, RecordModelAttempt}
  alias Jido.AI.Reasoning.ChainOfDraft.Actions.Complete

  use Jido.Flow,
    id: "jido.ai/reasoning/chain-of-draft/model-round",
    vsn: 1,
    name: "jido_ai_chain_of_draft_model_round",
    schema: Zoi.object(%{turn: Zoi.any()}),
    output_schema: Zoi.map()

  flow do
    step "project", action: ProjectConversation, params: %{turn: input(:turn)}

    step "model",
      action: CallModel,
      params: %{
        turn: result("project", :turn),
        context: result("project", :context),
        reasoning: %{method: :chain_of_draft},
        tools: false
      }

    step "output_guard",
      action: GuardOutput,
      params: %{turn: result("model", :turn), outcome: result("model", :outcome)}

    step "record_attempt",
      action: RecordModelAttempt,
      params: %{
        turn: result("model", :turn),
        outcome: result("model", :outcome),
        context: result("model", :context),
        output_allowed: result("output_guard", :allowed),
        output_reason: result("output_guard", :reason),
        reasoning: %{method: :chain_of_draft}
      }

    step "complete", action: Complete, params: %{turn: result("record_attempt", :turn)}
    output result("complete")
  end
end
