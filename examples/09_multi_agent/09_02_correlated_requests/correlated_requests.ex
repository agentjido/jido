defmodule Jido.Examples.CorrelatedRequests do
  @moduledoc "Commits pending work, accepts one correlated child result, and rejects stale replies."

  use Jido.Agent, name: "example_correlated_requests"

  state do
    schema Jido.Joi.object(%{
             request_id: Jido.Joi.string() |> Jido.Joi.default(""),
             status: Jido.Joi.enum([:idle, :waiting, :completed, :failed, :cancelled]) |> Jido.Joi.default(:idle),
             seen: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([]),
             result: Jido.Joi.integer() |> Jido.Joi.nullable() |> Jido.Joi.default(nil)
           })
  end

  routes do
    signal_source "/examples/multi_agent/correlated_requests"

    route "examples.multi_agent.requests.start", as: :request do
      action %{request_id: request_id, value: value},
        schema: Jido.Joi.object(%{request_id: Jido.Joi.string() |> Jido.Joi.min(1), value: Jido.Joi.integer()}),
        context: context do
        state = context.agent_state

        cond do
          state.status == :waiting ->
            {:error, Jido.Error.validation_error("a request is already waiting")}

          request_id in state.seen ->
            {:error, Jido.Error.validation_error("request ID is already used")}

          true ->
            candidate = %{
              state
              | request_id: request_id,
                status: :waiting,
                result: nil,
                seen: state.seen ++ [request_id]
            }

            {:ok, command_signal_1} =
              Jido.Examples.Worker.calculate_signal(%{
                request_id: request_id,
                job_id: request_id,
                tag: request_id,
                value: value
              })

            directives = [
              Jido.AgentServer.Directive.agent_start(Jido.Examples.Worker, request_id,
                restart: :temporary,
                opts: %{error_policy: :stop_on_error, exec_opts: [timeout: 1000]}
              ),
              Jido.Agent.Directive.agent_send(
                request_id,
                command_signal_1
              )
            ]

            {:ok, candidate, directives}
        end
      end
    end

    route "examples.multi_agent.requests.cancel", as: :cancel do
      action %{request_id: request_id},
        schema: Jido.Joi.object(%{request_id: Jido.Joi.string()}),
        context: context do
        state = context.agent_state

        if state.request_id == request_id and state.status == :waiting do
          {:ok, %{state | status: :cancelled}, [Jido.AgentServer.Directive.agent_stop(request_id)]}
        else
          {:error, Jido.Error.validation_error("request is not waiting")}
        end
      end
    end

    route "examples.multi_agent.worker.result" do
      action input,
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string(),
            job_id: Jido.Joi.string(),
            tag: Jido.Joi.string(),
            value: Jido.Joi.integer()
          }),
        context: context do
        state = context.agent_state

        if input.request_id == state.request_id and input.job_id == state.request_id and
             input.tag == state.request_id and state.status == :waiting do
          {:ok, %{state | status: :completed, result: input.value},
           [Jido.AgentServer.Directive.agent_stop(state.request_id)]}
        else
          {:error, Jido.Error.validation_error("result is stale or unrelated")}
        end
      end
    end

    route "jido.agent.child.started", Jido.Examples.Support.KeepState

    route "jido.agent.child.exit" do
      action input,
        schema:
          Jido.Joi.object(%{
            tag: Jido.Joi.any(),
            child_id: Jido.Joi.string(),
            pid: Jido.Joi.any(),
            reason: Jido.Joi.any()
          }),
        context: context do
        state = context.agent_state

        if input.tag == state.request_id and state.status == :waiting,
          do: {:ok, %{state | status: :failed}},
          else: {:ok, state}
      end
    end
  end
end
