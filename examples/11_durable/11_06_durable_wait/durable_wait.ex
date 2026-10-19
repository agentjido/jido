defmodule Jido.Examples.Durable.DurableWait do
  @moduledoc "Stores an approval wait as Agent state between completed Flow Turns."
  use Jido.Agent, name: "durable_approval_wait"

  agent do
    schema Zoi.object(%{
             request_id: Zoi.string() |> Zoi.default(""),
             deadline: Zoi.integer() |> Zoi.default(0),
             status:
               Zoi.enum([:idle, :waiting, :approved, :expired, :cancelled])
               |> Zoi.default(:idle)
           })
  end

  routes do
    signal_source "/examples/durable/wait"
    route "examples.durable.wait.request", Jido.Examples.Durable.DurableWait.Request, as: :request
    route "examples.durable.wait.resolve", Jido.Examples.Durable.DurableWait.Resolve, as: :resolve
  end
end

defmodule Jido.Examples.Durable.DurableWait.Request do
  @moduledoc "Commits a wait and its absolute deadline, then releases the Turn."
  use Jido.Flow,
    name: "durable_wait_request",
    schema: Zoi.object(%{request_id: Zoi.string() |> Zoi.min(1), deadline: Zoi.integer()})

  flow do
    step "request", request <- input(), inline: [context: context] do
      if context.agent_state.status == :idle do
        {:ok, %{request_id: request.request_id, deadline: request.deadline, status: :waiting}}
      else
        {:error, Jido.Action.Error.validation_error("a request already exists")}
      end
    end

    output result("request")
  end
end

defmodule Jido.Examples.Durable.DurableWait.Resolve do
  @moduledoc "Consumes one approval or cancellation; an elapsed deadline becomes expired."
  use Jido.Flow,
    name: "durable_wait_resolve",
    schema:
      Zoi.object(%{
        request_id: Zoi.string() |> Zoi.min(1),
        decision: Zoi.enum([:approve, :cancel])
      })

  flow do
    step "resolve", input <- input(), inline: [context: context] do
      state = context.agent_state

      if state.status == :waiting and state.request_id == input.request_id do
        status =
          cond do
            state.deadline <= System.system_time(:millisecond) -> :expired
            input.decision == :cancel -> :cancelled
            true -> :approved
          end

        {:ok, %{state | status: status}}
      else
        {:error, Jido.Action.Error.validation_error("no matching approval wait")}
      end
    end

    output result("resolve")
  end
end
