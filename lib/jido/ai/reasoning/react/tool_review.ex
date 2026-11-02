defmodule Jido.AI.Reasoning.ReAct.ToolReview do
  @moduledoc "Waits for a durable tool approval, denial, or timeout."

  alias Jido.AI.Reasoning.ReAct.Actions.{
    ExpandNext,
    RequestToolReview,
    ResolveToolReview
  }

  use Jido.Flow,
    id: "jido.ai/reasoning/react/tool-review",
    vsn: 1,
    name: "jido_ai_react_tool_review",
    schema: Zoi.object(%{turn: Zoi.any()}),
    output_schema: Zoi.map()

  flow do
    step "request",
      action: RequestToolReview,
      params: %{turn: input(:turn)}

    selection "decision" do
      needs ["request"]

      await("approved",
        event: "jido.ai.review.approved",
        match: %{
          review_id: result("request", [:turn, :review_id]),
          request_id: result("request", [:turn, :request_id]),
          run_id: result("request", [:turn, :run_id])
        }
      )

      await("denied",
        event: "jido.ai.review.denied",
        match: %{
          review_id: result("request", [:turn, :review_id]),
          request_id: result("request", [:turn, :request_id]),
          run_id: result("request", [:turn, :run_id])
        }
      )

      timer("expired", after_ms: 300_000)
    end

    invoke "next",
      decision: ResolveToolReview,
      expander: ExpandNext,
      params: %{
        turn: result("request", :turn),
        decision: result("decision")
      }

    output result("next")
  end
end
