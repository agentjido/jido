defmodule Jido.Examples.AI.SchemaOverrides.Reasoning do
  @moduledoc "A small reasoning Flow with application-defined input fields."

  alias Jido.Joi

  use Jido.Flow,
    id: "jido.ai/examples/reasoning/schema-overrides",
    vsn: 1,
    name: "schema_driven_overrides",
    schema:
      Joi.object(
        %{
          input: Joi.string(),
          greeting: Joi.string() |> Joi.default("Hello"),
          punctuation: Joi.string() |> Joi.default(".")
        },
        unrecognized_keys: :error
      ),
    output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})

  flow do
    step "answer",
         [
           input <- input(:input),
           greeting <- input(:greeting),
           punctuation <- input(:punctuation)
         ],
         inline: [context: context] do
      {:ok,
       %{
         state: context.agent_state,
         response: %{output: "#{greeting}, #{input}#{punctuation}"}
       }}
    end

    output result("answer")
  end
end

defmodule Jido.Examples.AI.SchemaOverrides.Agent do
  @moduledoc "An Agent with schema-validated reasoning defaults."

  use Jido.AI.Agent,
    name: "schema_overrides_agent",
    id: "jido.ai/examples/agents/schema-overrides",
    vsn: 1

  ai do
    reasoning Jido.Examples.AI.SchemaOverrides.Reasoning do
      greeting "Welcome"
      punctuation "!"
    end
  end
end
