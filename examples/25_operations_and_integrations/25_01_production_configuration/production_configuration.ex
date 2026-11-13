defmodule Jido.Examples.Operations.RuntimeAgent do
  @moduledoc "A small Agent used to prove supervised startup and shutdown."

  use Jido.Agent, name: "operations_runtime_agent"

  state do
    schema Jido.Joi.object(%{checks: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/operations/runtime"

    route "examples.operations.runtime.check", as: :check do
      action _input, context: context do
        {:ok, %{context.agent_state | checks: context.agent_state.checks + 1}}
      end
    end
  end
end

defmodule Jido.Examples.Operations.ConfiguredRuntime do
  @moduledoc "A host-application Jido instance with a stable namespace."

  use Jido,
    otp_app: :jido,
    namespace: "examples/operations/production"
end
