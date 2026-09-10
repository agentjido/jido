defmodule Jido.Examples.CorrelatedRequests do
  @moduledoc "Commits pending work, accepts one correlated child result, and rejects stale replies."

  use Jido.Agent, name: "example_correlated_requests"

  agent do
    schema Zoi.object(%{
             request_id: Zoi.string() |> Zoi.default(""),
             status:
               Zoi.enum([:idle, :waiting, :completed, :failed, :cancelled]) |> Zoi.default(:idle),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             result: Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil)
           })
  end

  routes do
    signal_source "/examples/multi_agent/correlated_requests"

    route "examples.multi_agent.requests.start" do
      action %{request_id: request_id, value: value},
        schema:
          Zoi.object(%{request_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        state = context.agent_state

        cond do
          state.status == :waiting ->
            {:error, Jido.Action.Error.validation_error("a request is already waiting")}

          request_id in state.seen ->
            {:error, Jido.Action.Error.validation_error("request ID is already used")}

          true ->
            candidate = %{
              state
              | request_id: request_id,
                status: :waiting,
                result: nil,
                seen: state.seen ++ [request_id]
            }

            directives = [
              Jido.Agent.Directive.spawn_child(Jido.Examples.Worker, request_id,
                restart: :temporary,
                opts: %{error_policy: :stop_on_error, exec_opts: [timeout: 1_000]}
              ),
              Jido.Agent.Directive.emit_to_child(
                request_id,
                Jido.Examples.Worker.calculate_signal!(request_id, request_id, request_id, value)
              )
            ]

            {:ok, candidate, directives}
        end
      end

      define :request, args: [:request_id, :value]
    end

    route "examples.multi_agent.requests.cancel" do
      action %{request_id: request_id},
        schema: Zoi.object(%{request_id: Zoi.string()}),
        context: context do
        state = context.agent_state

        if state.request_id == request_id and state.status == :waiting do
          {:ok, %{state | status: :cancelled}, [Jido.Agent.Directive.stop_child(request_id)]}
        else
          {:error, Jido.Action.Error.validation_error("request is not waiting")}
        end
      end

      define :cancel, args: [:request_id]
    end

    route "examples.multi_agent.worker.result" do
      action input,
        schema:
          Zoi.object(%{
            request_id: Zoi.string(),
            job_id: Zoi.string(),
            tag: Zoi.string(),
            value: Zoi.integer()
          }),
        context: context do
        state = context.agent_state

        if input.request_id == state.request_id and input.job_id == state.request_id and
             input.tag == state.request_id and state.status == :waiting do
          {:ok, %{state | status: :completed, result: input.value},
           [Jido.Agent.Directive.stop_child(state.request_id)]}
        else
          {:error, Jido.Action.Error.validation_error("result is stale or unrelated")}
        end
      end
    end

    route "jido.agent.child.started", Jido.Examples.Support.KeepState

    route "jido.agent.child.exit" do
      action input, context: context do
        state = context.agent_state

        if input.tag == state.request_id and state.status == :waiting,
          do: {:ok, %{state | status: :failed}},
          else: {:ok, state}
      end
    end
  end
end
