defmodule Jido.Examples.Guardrails.HumanReview.Prepare do
  use Jido.Action,
    name: "example_guardrail_prepare_review",
    schema:
      Jido.Joi.object(%{
        request_id: Jido.Joi.string() |> Jido.Joi.min(1),
        content_digest: Jido.Joi.string() |> Jido.Joi.min(1)
      })

  @impl true
  def run(params, _context), do: {:ok, Map.put(params, :status, :awaiting_review)}
end

defmodule Jido.Examples.Guardrails.HumanReview.Finalize do
  use Jido.Action, name: "example_guardrail_finalize_review"

  @impl true
  def run(%{request: request, decision: decision}, _context) do
    {:ok,
     %{
       request_id: request.request_id,
       content_digest: request.content_digest,
       status: String.to_existing_atom(decision.selected),
       evidence: decision.value
     }}
  end
end

defmodule Jido.Examples.Guardrails.HumanReview do
  use Jido.Flow,
    name: "example_guardrail_human_review",
    schema:
      Jido.Joi.object(%{
        request_id: Jido.Joi.string() |> Jido.Joi.min(1),
        content_digest: Jido.Joi.string() |> Jido.Joi.min(1)
      })

  alias Jido.Examples.Guardrails.HumanReview.{Finalize, Prepare}

  flow do
    step "prepare",
      action: Prepare,
      params: %{request_id: input(:request_id), content_digest: input(:content_digest)}

    selection "decision" do
      await "approved",
        event: "examples.guardrails.review.approved",
        match: %{request_id: result("prepare", :request_id)}

      await "denied",
        event: "examples.guardrails.review.denied",
        match: %{request_id: result("prepare", :request_id)}

      timer "expired", after_ms: 60_000
    end

    step "finalize",
      action: Finalize,
      params: %{request: result("prepare"), decision: result("decision")}

    output result("finalize")
  end
end
