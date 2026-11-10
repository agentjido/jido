defmodule Jido.Test.Agent.Authoring.Definitions.Alice do
  use Jido.Agent,
    name: "alice",
    description: "Accepts a greeting request and emits a greeting"

  state do
    schema Jido.Joi.object(%{
             greetings: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/alice"

    route "alice.greeting.requested", as: :greet do
      action %{name: name},
        schema: Jido.Joi.object(%{name: Jido.Joi.string()}),
        context: context do
        next_state = %{context.agent_state | greetings: context.agent_state.greetings + 1}
        {:ok, next_state, [emit("alice.greeting.produced", %{message: "Hello, #{name}!"})]}
      end
    end
  end
end
