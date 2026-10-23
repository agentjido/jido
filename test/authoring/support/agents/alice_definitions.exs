defmodule JidoTest.ComposableAgent.Definitions.Alice do
  use Jido.Agent,
    name: "alice",
    description: "Accepts a greeting request and emits a greeting"

  state do
    schema Zoi.object(%{
             greetings: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/alice"

    route "alice.greeting.requested", as: :greet do
      action %{name: name},
        schema: Zoi.object(%{name: Zoi.string()}),
        context: context,
        output_schema: Zoi.any() do
        next_state = %{context.agent_state | greetings: context.agent_state.greetings + 1}
        {:ok, next_state, [emit("alice.greeting.produced", %{message: "Hello, #{name}!"})]}
      end

      state(from: output())
    end
  end
end
