defmodule Jido.Examples.DistributedAgents.ApprovalDesk do
  @moduledoc "An approval Agent that can restore its waiting Turn on another host."

  alias Jido.{Joi, Signal}

  use Jido.Agent, name: "distributed_approval_desk"

  state do
    schema Joi.object(%{approved_requests: Joi.list(Joi.string()) |> Joi.default([])})
  end

  routes do
    route "examples.distribution.approval.request", __MODULE__.Approval, as: :request do
    end
  end

  @doc "Builds a request for approval."
  def request(id),
    do: Signal.new!("examples.distribution.approval.request", %{id: id}, source: "/examples/distribution")

  @doc "Builds the decision that resumes the waiting Turn."
  def approve(id),
    do: Signal.new!("examples.distribution.approval.approve", %{id: id}, source: "/examples/distribution")
end

defmodule Jido.Examples.DistributedAgents.ApprovalDesk.Approval do
  @moduledoc "Waits for approval of the requested ID before updating Agent state."

  alias Jido.Joi

  use Jido.Flow,
    name: "distributed_approval",
    schema: Joi.object(%{id: Joi.string() |> Joi.min(1)})

  flow do
    await "approval", event: "examples.distribution.approval.approve", match: %{id: input(:id)}

    step "record", data <- %{id: input(:id)}, inline: [context: context] do
      {:ok, %{approved_requests: context.agent_state.approved_requests ++ [data.id]}}
    end

    output result("record")
  end
end
