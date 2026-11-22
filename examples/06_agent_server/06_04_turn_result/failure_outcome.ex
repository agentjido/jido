defmodule Jido.Examples.FailureOutcome do
  @moduledoc "Shows failed and committed AgentServer Turn results."

  alias Jido.Joi

  use Jido.Agent, name: "runtime_failure_outcome"

  state do
    schema Joi.object(%{accepted: Joi.list(Joi.string()) |> Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/failure_outcome"
    route "examples.runtime.failure_outcome.reject", __MODULE__.Reject, as: :reject
    route "examples.runtime.failure_outcome.accept", __MODULE__.Accept, as: :accept
  end

  defmodule Reject do
    @moduledoc false
    use Jido.Action,
      name: "runtime_failure_outcome_reject",
      schema: Joi.object(%{reason: Joi.string() |> Joi.min(1)})

    def run(%{reason: reason}, _context) do
      {:error, Jido.Error.execution_error("Request was rejected", details: %{reason: reason})}
    end
  end

  defmodule Accept do
    @moduledoc false
    use Jido.Action,
      name: "runtime_failure_outcome_accept",
      schema: Joi.object(%{name: Joi.string() |> Joi.min(1)})

    def run(%{name: name}, context) do
      {:ok, %{context.agent_state | accepted: context.agent_state.accepted ++ [name]}}
    end
  end
end
