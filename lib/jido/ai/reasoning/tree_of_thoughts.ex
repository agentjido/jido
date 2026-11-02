defmodule Jido.AI.Reasoning.TreeOfThoughts do
  @moduledoc "Generates, evaluates, selects, and synthesizes a small thought tree."

  alias Jido.AI.Reasoning.Actions.{DecideInput, FinalizeTurn, GuardInput, StartRequest}
  alias Jido.AI.Reasoning.TreeOfThoughts.Actions.ExpandNext

  @default_instructions """
  Explore several different candidate paths. Evaluate weak and strong paths,
  select the useful candidates, and synthesize one final answer.
  """

  use Jido.Flow,
    id: "jido.ai/reasoning/tree-of-thoughts",
    vsn: 1,
    name: "jido_ai_reasoning_tree_of_thoughts",
    description: "Generate, evaluate, select, and synthesize candidate thoughts",
    schema:
      Zoi.object(
        %{
          input: Zoi.union([Zoi.string(), Zoi.list(Zoi.map())]),
          instructions: Zoi.string() |> Zoi.default(@default_instructions),
          model: Zoi.string() |> Zoi.default("openai:gpt-4o-mini"),
          options: Zoi.map() |> Zoi.default(%{max_tokens: 1536, temperature: 0.4}),
          prompt_cache:
            Zoi.object(
              %{
                enabled: Zoi.boolean() |> Zoi.default(false),
                ttl: Zoi.union([Zoi.string(), Zoi.integer(gte: 0)]) |> Zoi.optional()
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{enabled: false}),
          context:
            Zoi.object(
              %{
                max_messages: Zoi.integer(gte: 1, lte: 512) |> Zoi.default(64),
                max_bytes: Zoi.integer(gte: 1_024, lte: 2_000_000) |> Zoi.default(200_000)
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{max_messages: 64, max_bytes: 200_000}),
          limits:
            Zoi.object(
              %{
                elapsed_ms: Zoi.integer(gte: 1, lte: 3_600_000) |> Zoi.default(120_000),
                input_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.default(nil),
                output_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.default(nil),
                total_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.default(nil),
                total_cost: Zoi.number(gte: 0) |> Zoi.nullable() |> Zoi.default(nil)
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{
              elapsed_ms: 120_000,
              input_tokens: nil,
              output_tokens: nil,
              total_tokens: nil,
              total_cost: nil
            })
        },
        unrecognized_keys: :error
      ),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  @doc "Returns the default Tree of Thoughts instructions."
  @spec default_instructions() :: String.t()
  def default_instructions, do: @default_instructions

  flow do
    step "start_request",
      action: StartRequest,
      params: %{
        flow: %{id: "jido.ai/reasoning/tree-of-thoughts", vsn: 1},
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        fallback_models: [],
        options: input(:options),
        prompt_cache: input(:prompt_cache),
        context_window: input(:context),
        max_model_calls: 3,
        max_retries: 0,
        max_elapsed_ms: input([:limits, :elapsed_ms]),
        max_input_tokens: input([:limits, :input_tokens]),
        max_output_tokens: input([:limits, :output_tokens]),
        max_total_tokens: input([:limits, :total_tokens]),
        max_total_cost: input([:limits, :total_cost])
      }

    step "input_guard", action: GuardInput, params: %{turn: result("start_request")}

    invoke "reason",
      decision: DecideInput,
      expander: ExpandNext,
      params: %{turn: result("start_request"), guard: result("input_guard")}

    step "finalize", action: FinalizeTurn, params: %{outcome: result("reason")}
    output result("finalize")
  end
end
