defmodule Jido.Examples.AgentServer.PureHostedParity.Counter do
  use Jido.Agent,
    name: "example_pure_hosted_parity",
    description: "Counts one command and returns a correlated reply"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/agent-server/parity"

    route "examples.agent_server.parity.increment", as: :increment do
      action %{amount: amount},
        schema: Jido.Joi.object(%{amount: Jido.Joi.integer()}),
        output_schema:
          Jido.Joi.object(%{
            state: Jido.Joi.object(%{count: Jido.Joi.integer()}),
            reply: Jido.Joi.object(%{count: Jido.Joi.integer()})
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
