defmodule Jido.AI.Reasoning.ReAct.AfterReview do
  alias Jido.AI.Reasoning.ReAct.Actions.{Advance, ExpandNext, FinishLoop, Resume}
  alias Jido.Joi

  @moduledoc false

  use Jido.Flow,
    id: "jido.ai/reasoning/react/after-review",
    vsn: 1,
    name: "jido_ai_react_after_review",
    description: "Resume the fixed ReAct loop after an approved tool round",
    schema: Joi.object(%{turn: Joi.any(), routes: Joi.map()}),
    output_schema: Joi.map()

  flow do
    step "initialize",
      action: Resume,
      params: %{turn: input(:turn)}

    iterate "loop" do
      state(Joi.map(), initial: result("initialize"))
      action(Advance)
      params(%{state: state()})
      update(body_result())
      while(state(:done) == false)
      max_iterations(17)
    end

    invoke "continuation",
      decision: FinishLoop,
      expander: ExpandNext,
      params: %{state: result("loop", :state)}

    output result("continuation")
  end
end
