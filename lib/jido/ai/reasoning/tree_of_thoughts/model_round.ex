defmodule Jido.AI.Reasoning.TreeOfThoughts.ModelRound do
  @moduledoc "Runs one phase of the bounded Tree of Thoughts graph."

  alias Jido.AI.Reasoning.Actions.{CallModel, GuardOutput, ProjectConversation, RecordModelAttempt}

  alias Jido.AI.Reasoning.TreeOfThoughts.Actions.{
    AcceptOutput,
    ExpandNext,
    PrepareCall,
    SelectThoughts
  }

  use Jido.Flow,
    id: "jido.ai/reasoning/tree-of-thoughts/model-round",
    vsn: 1,
    name: "jido_ai_tree_of_thoughts_model_round",
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
        reasoning: %{
          method: :tree_of_thoughts,
          phase: result("prepare", [:state, :phase])
        },
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
        reasoning: %{
          method: :tree_of_thoughts,
          phase: result("prepare", [:state, :phase])
        },
        persist_message: result("prepare", :persist_message)
      }

    step "accept",
      action: AcceptOutput,
      params: %{
        state: result("prepare", :state),
        turn: result("record_attempt", :turn)
      }

    invoke "next",
      decision: SelectThoughts,
      expander: ExpandNext,
      params: result("accept")

    output result("next")
  end
end
