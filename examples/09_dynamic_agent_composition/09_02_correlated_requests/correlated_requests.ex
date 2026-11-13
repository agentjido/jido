defmodule Jido.Examples.CorrelatedRequests do
  @moduledoc "Coordinates two durable Agents with explicit stable Addresses."

  use Jido.Agent, name: "example_correlated_requests"

  state do
    schema Jido.Joi.object(%{
             request_id: Jido.Joi.string() |> Jido.Joi.default(""),
             status: Jido.Joi.enum([:idle, :waiting, :completed]) |> Jido.Joi.default(:idle),
             result: Jido.Joi.integer() |> Jido.Joi.nullable() |> Jido.Joi.default(nil)
           })
  end

  routes do
    signal_source "/examples/multi_agent/correlated_requests"

    route "examples.multi_agent.requests.start", as: :request do
      action %{request_id: request_id},
        schema: Jido.Joi.object(%{request_id: Jido.Joi.string() |> Jido.Joi.min(1)}),
        context: context do
        if context.agent_state.status == :waiting do
          {:error, Jido.Error.validation_error("a request is already waiting")}
        else
          {:ok, %{context.agent_state | request_id: request_id, status: :waiting, result: nil}}
        end
      end
    end

    route "examples.multi_agent.requests.complete", as: :complete do
      action %{request_id: request_id, value: value},
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer()
          }),
        context: context do
        state = context.agent_state

        if state.status == :waiting and state.request_id == request_id do
          {:ok, %{state | status: :completed, result: value}}
        else
          {:error, Jido.Error.validation_error("result is stale or unrelated")}
        end
      end
    end
  end

  @doc "Runs one request through the coordinator and worker stable Addresses."
  def run(instance, coordinator_address, worker_address, request_id, value) do
    with {:ok, request} <- request_signal(%{request_id: request_id}),
         {:ok, _turn} <- Jido.call(instance, coordinator_address, request),
         {:ok, calculation} <-
           Jido.Examples.Worker.calculate_signal(%{request_id: request_id, value: value}),
         {:ok, _worker_turn} <- Jido.call(instance, worker_address, calculation),
         {:ok, worker} <- Jido.activate_agent(instance, worker_address),
         result <- List.last(Jido.AgentServer.snapshot(worker).agent.state.completed),
         {:ok, completion} <- complete_signal(result),
         {:ok, coordinator_turn} <- Jido.call(instance, coordinator_address, completion) do
      {:ok, coordinator_turn}
    end
  end
end
