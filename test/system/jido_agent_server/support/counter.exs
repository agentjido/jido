defmodule Jido.Test.AgentServer.System.Add do
  use Jido.Action,
    name: "system_runtime_add",
    schema:
      Jido.Joi.object(%{
        delta: Jido.Joi.integer(),
        secret: Jido.Joi.string() |> Jido.Joi.optional()
      })

  @impl true
  def run(%{delta: delta}, %{agent_state: state}) do
    {:ok, %{state | count: state.count + delta}}
  end
end

defmodule Jido.Test.AgentServer.System.Counter do
  use Jido.Agent, name: "system_runtime_counter"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    route "system.runtime.add", Jido.Test.AgentServer.System.Add
  end
end
