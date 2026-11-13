defmodule Jido.Examples.Patterns.HumanApproval.Submit do
  use Jido.Action, name: "example_human_approval_submit"

  @impl true
  def run(%{request_id: request_id}, _context) do
    {:ok, %{request_id: request_id, status: :pending}, [{:submitted, request_id}]}
  end
end

defmodule Jido.Examples.Patterns.HumanApproval.Finalize do
  use Jido.Action, name: "example_human_approval_finalize"

  @impl true
  def run(%{request: request, decision: decision}, _context) do
    {:ok, %{request_id: request.request_id, status: String.to_existing_atom(decision.selected)}}
  end
end

defmodule Jido.Examples.Patterns.HumanApproval do
  use Jido.Flow, name: "example_human_approval"

  alias Jido.Examples.Patterns.HumanApproval.{Finalize, Submit}

  flow do
    step "submit", action: Submit, params: %{request_id: input(:request_id)}

    selection "decision" do
      await "approved",
        event: "approval.approved",
        match: %{request_id: result("submit", :request_id)}

      await "denied",
        event: "approval.denied",
        match: %{request_id: result("submit", :request_id)}

      timer "expired", after_ms: 60_000
    end

    step "finalize",
      action: Finalize,
      params: %{request: result("submit"), decision: result("decision")}

    output result("finalize")
  end
end
