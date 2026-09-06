defmodule Jido.Examples.CorrelatedRequests.Request do
  @moduledoc false
  use Jido.Action,
    name: "example_correlated_request",
    schema: Zoi.object(%{request_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()})

  alias Jido.Agent.Directive
  alias Jido.Examples.Worker

  def run(input, %{agent_state: state} = context) do
    cond do
      state.status == :waiting ->
        {:error, Jido.Action.Error.validation_error("a request is already waiting")}

      input.request_id in state.seen ->
        {:error, Jido.Action.Error.validation_error("request ID is already used")}

      true ->
        tag = input.request_id

        next = %{
          state
          | request_id: tag,
            status: :waiting,
            result: nil,
            seen: state.seen ++ [tag]
        }

        {:ok, next,
         [
           Directive.spawn_agent(Map.get(context, :worker, Worker), tag,
             restart: :temporary,
             opts: %{error_policy: :stop_on_error, exec_opts: [timeout: 1_000]}
           ),
           Directive.emit_to_child(tag, Worker.calculate_signal!(tag, tag, tag, input.value))
         ]}
    end
  end
end

defmodule Jido.Examples.CorrelatedRequests.Result do
  @moduledoc false
  use Jido.Action,
    name: "example_correlated_result",
    schema:
      Zoi.object(%{
        request_id: Zoi.string(),
        job_id: Zoi.string(),
        tag: Zoi.string(),
        value: Zoi.integer()
      })

  def run(
        %{request_id: id, job_id: id, tag: id, value: value},
        %{agent_state: %{request_id: id, status: :waiting} = state}
      ) do
    {:ok, %{state | status: :completed, result: value}, [Jido.Agent.Directive.stop_child(id)]}
  end

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("result is stale or unrelated")}
end

defmodule Jido.Examples.CorrelatedRequests.Cancel do
  @moduledoc false
  use Jido.Action,
    name: "example_correlated_cancel",
    schema: Zoi.object(%{request_id: Zoi.string()})

  def run(%{request_id: id}, %{agent_state: %{request_id: id, status: :waiting} = state}) do
    {:ok, %{state | status: :cancelled}, [Jido.Agent.Directive.stop_child(id)]}
  end

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("request is not waiting")}
end

defmodule Jido.Examples.CorrelatedRequests.Exit do
  @moduledoc false
  use Jido.Action, name: "example_correlated_exit"

  def run(%{tag: id}, %{agent_state: %{request_id: id, status: :waiting} = state}),
    do: {:ok, %{state | status: :failed}}

  def run(_, %{agent_state: state}), do: {:ok, state}
end

defmodule Jido.Examples.CorrelatedRequests do
  @moduledoc "Commits pending work, receives a correlated child result, and rejects stale replies."
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
    signal_source "/examples/requests"

    route "examples.requests.start", Jido.Examples.CorrelatedRequests.Request do
      define :request, args: [:request_id, :value]
    end

    route "examples.requests.cancel", Jido.Examples.CorrelatedRequests.Cancel do
      define :cancel, args: [:request_id]
    end

    route "examples.work.result", Jido.Examples.CorrelatedRequests.Result
    route "jido.agent.child.started", Jido.Examples.KeepState
    route "jido.agent.child.exit", Jido.Examples.CorrelatedRequests.Exit
  end
end
