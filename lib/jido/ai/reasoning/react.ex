defmodule Jido.AI.Reasoning.ReAct do
  @moduledoc """
  The canonical graph-first ReAct reasoning recipe.

  The root Flow starts the request, applies the default input guard, invokes
  the ReAct loop, and finalizes the terminal outcome. Model rounds, tool
  review, and all recipe Actions are public modules under this namespace.
  """

  alias Jido.AI.Reasoning.Actions.{DecideInput, FinalizeTurn, GuardInput, StartRequest}
  alias Jido.AI.Reasoning.ReAct.Actions.ExpandNext

  @default_instructions "Answer concisely. Use the available tools when they help. You can request multiple tools in one response."

  use Jido.Flow,
    id: "jido.ai/reasoning/react",
    vsn: 1,
    name: "jido_ai_reasoning_react",
    description: "A persisted conversation, model, and parallel tool graph",
    schema:
      Zoi.object(
        %{
          input: Zoi.union([Zoi.string(), Zoi.list(Zoi.map())]),
          instructions: Zoi.string() |> Zoi.default(@default_instructions),
          model: Zoi.string() |> Zoi.default("openai:gpt-4o-mini"),
          fallback_models: Zoi.list(Zoi.string()) |> Zoi.default([]),
          options:
            Zoi.map()
            |> Zoi.default(%{max_tokens: 128, receive_timeout: 30_000, temperature: 0.0}),
          prompt_cache:
            Zoi.object(
              %{
                enabled: Zoi.boolean() |> Zoi.default(false),
                ttl:
                  Zoi.union([Zoi.string(), Zoi.integer(gte: 0)])
                  |> Zoi.optional()
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{enabled: false}),
          stream: Zoi.boolean() |> Zoi.default(false),
          output_schema: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil),
          review_tools: Zoi.boolean() |> Zoi.default(false),
          tool_policy:
            Zoi.object(
              %{
                visible: Zoi.list(Zoi.string()) |> Zoi.default([]),
                hidden: Zoi.list(Zoi.string()) |> Zoi.default([]),
                review: Zoi.list(Zoi.string()) |> Zoi.default([]),
                requirement:
                  Zoi.enum([:optional, :required, :per_turn, :disabled])
                  |> Zoi.default(:optional),
                reason: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{
              visible: [],
              hidden: [],
              review: [],
              requirement: :optional,
              reason: nil
            }),
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
                model_calls: Zoi.integer(gte: 1, lte: 16) |> Zoi.default(8),
                tool_rounds: Zoi.integer(gte: 0, lte: 8) |> Zoi.default(4),
                tool_calls: Zoi.integer(gte: 1, lte: 16) |> Zoi.default(8),
                retries: Zoi.integer(gte: 0, lte: 4) |> Zoi.default(1),
                elapsed_ms: Zoi.integer(gte: 1, lte: 3_600_000) |> Zoi.default(120_000),
                input_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.default(nil),
                output_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.default(nil),
                total_tokens: Zoi.integer(gte: 1) |> Zoi.nullable() |> Zoi.default(nil),
                total_cost: Zoi.number(gte: 0) |> Zoi.nullable() |> Zoi.default(nil),
                tool_output_bytes: Zoi.integer(gte: 256, lte: 1_000_000) |> Zoi.default(16_384)
              },
              unrecognized_keys: :error
            )
            |> Zoi.default(%{
              model_calls: 8,
              tool_rounds: 4,
              tool_calls: 8,
              retries: 1,
              elapsed_ms: 120_000,
              input_tokens: nil,
              output_tokens: nil,
              total_tokens: nil,
              total_cost: nil,
              tool_output_bytes: 16_384
            })
        },
        unrecognized_keys: :error
      ),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  flow do
    step "start_request",
      action: StartRequest,
      params: %{
        flow: %{id: "jido.ai/reasoning/react", vsn: 1},
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        fallback_models: input(:fallback_models),
        options: input(:options),
        prompt_cache: input(:prompt_cache),
        output_schema: input(:output_schema),
        stream: input(:stream),
        review_tools: input(:review_tools),
        tool_policy: input(:tool_policy),
        context_window: input(:context),
        max_tool_rounds: input([:limits, :tool_rounds]),
        max_tool_calls: input([:limits, :tool_calls]),
        max_model_calls: input([:limits, :model_calls]),
        max_retries: input([:limits, :retries]),
        max_elapsed_ms: input([:limits, :elapsed_ms]),
        max_input_tokens: input([:limits, :input_tokens]),
        max_output_tokens: input([:limits, :output_tokens]),
        max_total_tokens: input([:limits, :total_tokens]),
        max_total_cost: input([:limits, :total_cost]),
        max_tool_output_bytes: input([:limits, :tool_output_bytes])
      }

    step "input_guard",
      action: GuardInput,
      params: %{turn: result("start_request")}

    invoke "loop",
      decision: DecideInput,
      expander: ExpandNext,
      params: %{
        turn: result("start_request"),
        guard: result("input_guard")
      }

    step "finalize",
      action: FinalizeTurn,
      params: %{outcome: result("loop")}

    output result("finalize")
  end
end
