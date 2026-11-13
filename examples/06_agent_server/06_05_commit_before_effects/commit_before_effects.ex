defmodule Jido.Examples.AgentServer.CommitBeforeEffects.FailingDelivery do
  use Jido.Agent.Directive

  @schema Jido.Joi.struct(
            __MODULE__,
            %{delivery_id: Jido.Joi.string() |> Jido.Joi.min(1)},
            coerce: true
          )

  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.AgentServer.CommitBeforeEffects.DeliveryPlugin do
  use Jido.Plugin

  alias Jido.Examples.AgentServer.CommitBeforeEffects.FailingDelivery

  @impl true
  def directives(_options), do: [FailingDelivery]

  @impl true
  def dispatch(_runtime, %FailingDelivery{} = directive, context, _options) do
    server = Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)
    snapshot = Jido.AgentServer.snapshot(server)
    send(context.turn_context.observer, {:delivery_attempted, directive.delivery_id, snapshot})
    {:error, Jido.Error.execution_error("delivery failed after commit")}
  end
end

defmodule Jido.Examples.AgentServer.CommitBeforeEffects.Counter do
  use Jido.Agent,
    name: "example_commit_before_effects",
    plugins: [Jido.Examples.AgentServer.CommitBeforeEffects.DeliveryPlugin]

  alias Jido.Examples.AgentServer.CommitBeforeEffects.FailingDelivery

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/agent-server/commit-before-effects"

    route "examples.agent_server.commit_before_effects.increment", as: :increment do
      action %{delivery_id: delivery_id},
        schema: Jido.Joi.object(%{delivery_id: Jido.Joi.string() |> Jido.Joi.min(1)}),
        context: context do
        state = %{context.agent_state | count: context.agent_state.count + 1}
        {:ok, state, [%FailingDelivery{delivery_id: delivery_id}]}
      end
    end
  end
end
