defmodule Jido.Examples.Collaboration.ServiceOperations.Intake do
  use Jido.Action, name: "example_service_operations_intake"

  @impl true
  def run(%{request_id: request_id, description: description, priority: priority}, _context) do
    {:ok, %{request_id: request_id, description: description, priority: priority, status: :accepted}}
  end
end

defmodule Jido.Examples.Collaboration.ServiceOperations.Assign do
  use Jido.Action, name: "example_service_operations_assign"

  @impl true
  def run(%{ticket: ticket}, _context) do
    team = if ticket.priority == :high, do: "senior-operations", else: "operations"
    {:ok, Map.merge(ticket, %{assigned_team: team, status: :assigned})}
  end
end

defmodule Jido.Examples.Collaboration.ServiceOperations.QualityReview do
  use Jido.Action, name: "example_service_operations_quality_review"

  @impl true
  def run(%{assignment: assignment}, _context) do
    {:ok, Map.merge(assignment, %{quality: :passed, status: :awaiting_approval})}
  end
end

defmodule Jido.Examples.Collaboration.ServiceOperations.Finalize do
  use Jido.Action, name: "example_service_operations_finalize"

  @impl true
  def run(%{review: review, decision: decision}, _context) do
    {:ok,
     Map.merge(review, %{
       status: String.to_existing_atom(decision.selected),
       approval_evidence: decision.value
     })}
  end
end

defmodule Jido.Examples.Collaboration.ServiceOperations do
  use Jido.Flow,
    name: "example_service_operations_team",
    schema:
      Jido.Joi.object(%{
        request_id: Jido.Joi.string(),
        description: Jido.Joi.string() |> Jido.Joi.min(1),
        priority: Jido.Joi.enum([:normal, :high])
      })

  alias Jido.Examples.Collaboration.ServiceOperations.{Assign, Finalize, Intake, QualityReview}

  flow do
    step "intake",
      action: Intake,
      params: %{
        request_id: input(:request_id),
        description: input(:description),
        priority: input(:priority)
      }

    step "assign", action: Assign, params: %{ticket: result("intake")}
    step "quality", action: QualityReview, params: %{assignment: result("assign")}

    selection "approval" do
      await "approved",
        event: "examples.service_operations.approved",
        match: %{request_id: result("quality", :request_id)}

      await "cancelled",
        event: "examples.service_operations.cancelled",
        match: %{request_id: result("quality", :request_id)}

      timer "escalated", after_ms: 60_000
    end

    step "finalize",
      action: Finalize,
      params: %{review: result("quality"), decision: result("approval")}

    output result("finalize")
  end
end
