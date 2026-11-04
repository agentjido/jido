defmodule Jido.Examples.FailureOutcome do
  @moduledoc """
  Shows precommit failure and postcommit error reporting in one Agent.
  """
  use Jido.Agent, name: "runtime_failure_outcome"

  state do
    schema Jido.Joi.object(%{accepted: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/failure_outcome"
    route "examples.runtime.failure_outcome.reject", __MODULE__.Reject, as: :reject
    route "examples.runtime.failure_outcome.report", __MODULE__.Report, as: :report
  end

  defmodule Reject do
    @moduledoc false
    use Jido.Action,
      name: "runtime_failure_outcome_reject",
      schema: Jido.Joi.object(%{reason: Jido.Joi.string() |> Jido.Joi.min(1)})

    def run(%{reason: reason}, _context) do
      {:error, Jido.Error.execution_error("Request was rejected", details: %{reason: reason})}
    end
  end

  defmodule Report do
    @moduledoc false
    use Jido.Action,
      name: "runtime_failure_outcome_report",
      schema: Jido.Joi.object(%{name: Jido.Joi.string() |> Jido.Joi.min(1)})

    alias Jido.AgentServer.Directive

    def run(%{name: name}, context) do
      state = %{context.agent_state | accepted: context.agent_state.accepted ++ [name]}
      error = Jido.Error.execution_error("Postcommit notification failed", details: %{name: name})
      {:ok, state, [Directive.error_report(error, :notification)]}
    end
  end
end
