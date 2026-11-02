defmodule Jido.AI.Reasoning.Adaptive do
  alias Jido.Joi
  @moduledoc "Selects one existing reasoning Flow with a small local heuristic."

  alias Jido.AI.Reasoning.Adaptive.Actions.{Expand, Select}

  use Jido.Flow,
    id: "jido.ai/reasoning/adaptive",
    vsn: 1,
    name: "jido_ai_reasoning_adaptive",
    description: "A local decision followed by one normal reasoning Flow",
    schema:
      Joi.object(
        %{
          input: Joi.union([Joi.string(), Joi.list(Joi.map())]),
          instructions: Joi.string() |> Joi.optional(),
          model: Joi.string() |> Joi.optional(),
          options: Joi.map() |> Joi.optional(),
          prompt_cache:
            Joi.object(
              %{
                enabled: Joi.boolean() |> Joi.default(false),
                ttl: Joi.union([Joi.string(), Joi.integer(gte: 0)]) |> Joi.optional()
              },
              unrecognized_keys: :error
            )
            |> Joi.optional(),
          context:
            Joi.object(
              %{
                max_messages: Joi.integer(gte: 1, lte: 512) |> Joi.default(64),
                max_bytes: Joi.integer(gte: 1_024, lte: 2_000_000) |> Joi.default(200_000)
              },
              unrecognized_keys: :error
            )
            |> Joi.optional(),
          limits:
            Joi.object(
              %{
                elapsed_ms: Joi.integer(gte: 1, lte: 3_600_000) |> Joi.optional(),
                input_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.optional(),
                output_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.optional(),
                total_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.optional(),
                total_cost: Joi.number(gte: 0) |> Joi.nullable() |> Joi.optional()
              },
              unrecognized_keys: :preserve
            )
            |> Joi.optional(),
          strategy:
            Joi.enum([
              :react,
              :chain_of_thought,
              :chain_of_draft,
              :algorithm_of_thoughts,
              :tree_of_thoughts,
              :graph_of_thoughts,
              :trm
            ])
            |> Joi.nullable()
            |> Joi.default(nil)
        },
        unrecognized_keys: :preserve
      ),
    output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})

  flow do
    invoke "reason", decision: Select, expander: Expand, params: input()
    output result("reason")
  end
end
