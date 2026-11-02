defmodule Jido.AI.Reasoning.TRM.ModelRound do
  @moduledoc "Runs one phase of the bounded TRM revision cycle."

  alias Jido.AI.Reasoning.Actions.{CallModel, GuardOutput, ProjectConversation, RecordModelAttempt}
  alias Jido.AI.Reasoning.TRM.Actions.{Advance, ExpandNext, PrepareCall}

  use Jido.Flow,
    id: "jido.ai/reasoning/trm/model-round",
    vsn: 1,
    name: "jido_ai_trm_model_round",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  flow do
    step "prepare", action: PrepareCall, params: %{state: input()}

    step "project",
      action: ProjectConversation,
      params: %{turn: result("prepare", [:state, :turn])}

    step "model",
      action: CallModel,
      params: %{
        turn: result("project", :turn),
        context: result("project", :context),
        reasoning: %{method: :trm, phase: result("prepare", [:state, :phase])},
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
        reasoning: %{method: :trm, phase: result("prepare", [:state, :phase])},
        persist_message: result("prepare", :persist_message)
      }

    invoke "advance",
      decision: Advance,
      expander: ExpandNext,
      params: %{
        state: result("prepare", :state),
        turn: result("record_attempt", :turn)
      }

    output result("advance")
  end
end
