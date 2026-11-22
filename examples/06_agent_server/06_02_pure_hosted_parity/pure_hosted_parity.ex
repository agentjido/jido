defmodule Jido.Examples.AgentServer.PureHostedParity.Counter do
  alias Jido.Joi

  use Jido.Agent,
    name: "example_pure_hosted_parity",
    description: "Counts one command and returns a correlated reply"

  state do
    schema Joi.object(%{count: Joi.integer() |> Joi.default(0)})
  end

  routes do
    signal_source "/examples/agent-server/parity"

    route "examples.agent_server.parity.increment", as: :increment do
      action %{amount: amount},
        schema: Joi.object(%{amount: Joi.integer()}),
        output_schema:
          Joi.object(%{
            state: Joi.object(%{count: Joi.integer()}),
            reply: Joi.object(%{count: Joi.integer()})
          }),
        context: context do
        state = %{context.agent_state | count: context.agent_state.count + amount}
        {:ok, %{state: state, reply: %{count: state.count}}}
      end

      state(from: output(:state))
      reply("examples.agent_server.parity.incremented", from: output(:reply))
    end
  end
end
