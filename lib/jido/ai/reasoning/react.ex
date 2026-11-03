defmodule Jido.AI.Reasoning.ReAct do
  alias Jido.Joi

  @moduledoc """
  The canonical graph-first ReAct reasoning recipe.

  The root Flow starts the request, applies the default input guard, runs one
  fixed Iterate graph, and finalizes the terminal outcome. Model rounds, tool
  review, and all recipe Actions are public modules under this namespace.
  """

  alias Jido.AI.Reasoning.Actions.{FinalizeTurn, GuardInput, StartRequest}
  alias Jido.AI.Reasoning.ReAct.Actions.{Advance, ExpandNext, FinishLoop, Initialize}

  @default_instructions "Answer concisely. Use the available tools when they help. You can request multiple tools in one response."

  use Jido.Flow,
    id: "jido.ai/reasoning/react",
    vsn: 1,
    name: "jido_ai_reasoning_react",
    description: "A persisted conversation, model, and parallel tool graph",
    schema:
      Joi.object(
        %{
          input: Joi.union([Joi.string(), Joi.list(Joi.map())]),
          instructions: Joi.string() |> Joi.default(@default_instructions),
          model: Joi.string() |> Joi.default("openai:gpt-4o-mini"),
          fallback_models: Joi.list(Joi.string()) |> Joi.default([]),
          options:
            Joi.map()
            |> Joi.default(%{}),
          prompt_cache:
            Joi.object(
              %{
                enabled: Joi.boolean() |> Joi.default(false),
                ttl:
                  Joi.union([Joi.string(), Joi.integer(gte: 0)])
                  |> Joi.optional()
              },
              unrecognized_keys: :error
            )
            |> Joi.default(%{enabled: false}),
          stream: Joi.boolean() |> Joi.default(false),
          output_schema: Joi.map() |> Joi.nullable() |> Joi.default(nil),
          review_tools: Joi.boolean() |> Joi.default(false),
          tool_policy:
            Joi.object(
              %{
                visible: Joi.list(Joi.string()) |> Joi.default([]),
                hidden: Joi.list(Joi.string()) |> Joi.default([]),
                review: Joi.list(Joi.string()) |> Joi.default([]),
                requirement:
                  Joi.enum([:optional, :required, :per_turn, :disabled])
                  |> Joi.default(:optional),
                reason: Joi.string() |> Joi.nullable() |> Joi.default(nil)
              },
              unrecognized_keys: :error
            )
            |> Joi.default(%{
              visible: [],
              hidden: [],
              review: [],
              requirement: :optional,
              reason: nil
            }),
          context:
            Joi.object(
              %{
                max_messages: Joi.integer(gte: 1, lte: 512) |> Joi.default(64),
                max_bytes: Joi.integer(gte: 1_024, lte: 2_000_000) |> Joi.default(200_000)
              },
              unrecognized_keys: :error
            )
            |> Joi.default(%{max_messages: 64, max_bytes: 200_000}),
          limits:
            Joi.object(
              %{
                model_calls: Joi.integer(gte: 1, lte: 16) |> Joi.default(8),
                tool_rounds: Joi.integer(gte: 0, lte: 8) |> Joi.default(4),
                tool_calls: Joi.integer(gte: 1, lte: 16) |> Joi.default(8),
                retries: Joi.integer(gte: 0, lte: 4) |> Joi.default(1),
                elapsed_ms: Joi.integer(gte: 1, lte: 3_600_000) |> Joi.default(120_000),
                input_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.default(nil),
                output_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.default(nil),
                total_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.default(nil),
                total_cost: Joi.number(gte: 0) |> Joi.nullable() |> Joi.default(nil),
                tool_output_bytes: Joi.integer(gte: 256, lte: 1_000_000) |> Joi.default(16_384)
              },
              unrecognized_keys: :error
            )
            |> Joi.default(%{
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
    output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})

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

    step "initialize",
      action: Initialize,
      params: %{turn: result("start_request"), guard: result("input_guard")}

    iterate "loop" do
      state(Joi.map(), initial: result("initialize"))
      action(Advance)
      params(%{state: state()})
      update(body_result())
      while(state(:done) == false)
      max_iterations(17)
    end

    invoke "continuation",
      decision: FinishLoop,
      expander: ExpandNext,
      params: %{
        state: result("loop", :state)
      }

    step "finalize",
      action: FinalizeTurn,
      params: %{outcome: result("continuation")}

    output result("finalize")
  end
end
