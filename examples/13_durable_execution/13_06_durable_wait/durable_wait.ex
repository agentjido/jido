defmodule Jido.Examples.Durable.DurableWait do
  @moduledoc "Runs one durable approval Flow that releases its Worker while it waits."

  alias Jido.Joi

  use Jido.Agent, name: "durable_approval_wait"

  state do
    schema Joi.object(%{
             request_id: Joi.string() |> Joi.default(""),
             status: Joi.enum([:idle, :approved, :expired, :cancelled]) |> Joi.default(:idle)
           })
  end

  routes do
    signal_source "/examples/durable/wait"

    route "examples.durable.wait.request", Jido.Examples.Durable.DurableWait.Approval, as: :request do
    end
  end

  @doc "Builds a decision Signal for normal delivery through an Agent Address."
  def resolve_signal(%{request_id: id, decision: decision})
      when decision in [:approve, :cancel] do
    Jido.Signal.new("examples.durable.wait.#{decision}", %{request_id: id}, source: "/examples/durable/wait")
  end
end

defmodule Jido.Examples.Durable.DurableWait.Approval do
  @moduledoc "Waits for approval, cancellation, or a one-hour deadline in the same Turn."

  alias Jido.Joi

  use Jido.Flow,
    name: "durable_wait_approval",
    schema: Joi.object(%{request_id: Joi.string() |> Joi.min(1)})

  flow do
    step "request", request <- input(), inline: [context: context] do
      if context.agent_state.status == :idle do
        {:ok, request}
      else
        {:error, Jido.Error.validation_error("a request already exists")}
      end
    end

    selection "decision" do
      needs ["request"]

      await "approved",
        event: "examples.durable.wait.approve",
        match: %{request_id: result("request", :request_id)}

      await "cancelled",
        event: "examples.durable.wait.cancel",
        match: %{request_id: result("request", :request_id)}

      timer "expired", after_ms: 3_600_000
    end

    step "finish", values <- %{request: result("request"), decision: result("decision")} do
      status =
        case values.decision.selected do
          "approved" -> :approved
          "cancelled" -> :cancelled
          "expired" -> :expired
        end

      {:ok, %{request_id: values.request.request_id, status: status}}
    end

    output result("finish")
  end
end
