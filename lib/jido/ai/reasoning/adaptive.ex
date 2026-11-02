defmodule Jido.AI.Reasoning.Adaptive do
  @moduledoc "Selects one existing reasoning Flow with a small local heuristic."

  alias Jido.AI.Reasoning.Adaptive.Actions.{Expand, Select}

  use Jido.Flow,
    id: "jido.ai/reasoning/adaptive",
    vsn: 1,
    name: "jido_ai_reasoning_adaptive",
    description: "A local decision followed by one normal reasoning Flow",
    schema:
      Zoi.object(
        %{
          input: Zoi.union([Zoi.string(), Zoi.list(Zoi.map())]),
          instructions: Zoi.string() |> Zoi.optional(),
          model: Zoi.string() |> Zoi.optional(),
          options: Zoi.map() |> Zoi.optional(),
          prompt_cache:
            Zoi.object(
              %{
                enabled: Zoi.boolean() |> Zoi.default(false),
                ttl: Zoi.union([Zoi.string(), Zoi.integer(gte: 0)]) |> Zoi.optional()
              },
              unrecognized_keys: :error
            )
            |> Zoi.optional(),
          context:
            Zoi.object(
              %{
                max_messages: Zoi.integer(gte: 1, lte: 512) |> Zoi.default(64),
                max_bytes: Zoi.integer(gte: 1_024, lte: 2_000_000) |> Zoi.default(200_000)
              },
              unrecognized_keys: :error
            )
            |> Zoi.optional(),
          limits:
            Zoi.object(
              %{
                elapsed_ms: Zoi.integer(gte: 1, lte: 3_600_000) |> Zoi.optional(),
                input_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.optional(),
                output_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.optional(),
                total_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.optional(),
                total_cost: Zoi.number(gte: 0) |> Zoi.nullable() |> Zoi.optional()
              },
              unrecognized_keys: :preserve
            )
            |> Zoi.optional(),
          strategy:
            Zoi.enum([
              :react,
              :chain_of_thought,
              :chain_of_draft,
              :algorithm_of_thoughts,
              :tree_of_thoughts,
              :graph_of_thoughts,
              :trm
            ])
            |> Zoi.nullable()
            |> Zoi.default(nil)
        },
        unrecognized_keys: :preserve
      ),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  flow do
    invoke "reason", decision: Select, expander: Expand, params: input()
    output result("reason")
  end
end
