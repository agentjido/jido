defmodule Jido.AI.Reasoning.ChainOfThought do
  alias Jido.Joi

  @moduledoc """
  The canonical graph-first Chain of Thought reasoning recipe.

  The model produces a variable number of ordered reasoning steps and one
  conclusion in a single structured model call. It does not expose or depend
  on provider-hidden reasoning state.

  This recipe does not execute tools. Use `Jido.AI.Reasoning.ReAct` when the
  model must select and run Agent tools.
  """

  alias Jido.AI.Reasoning.Actions.{DecideInput, ExpandDecision, FinalizeTurn, GuardInput, StartRequest}

  @default_instructions """
  You are a helpful AI assistant that thinks through problems step by step.
  Return an ordered list of clear reasoning steps and one concise conclusion.
  """

  use Jido.Flow,
    id: "jido.ai/reasoning/chain-of-thought",
    vsn: 1,
    name: "jido_ai_reasoning_chain_of_thought",
    description: "A variable-length numbered reasoning chain and conclusion graph",
    schema:
      Joi.object(
        %{
          input: Joi.union([Joi.string(), Joi.list(Joi.map())]),
          instructions: Joi.string() |> Joi.default(@default_instructions),
          model: Joi.string() |> Joi.default("openai:gpt-4o-mini"),
          options:
            Joi.map()
            |> Joi.default(%{max_tokens: 512, receive_timeout: 30_000, temperature: 0.0}),
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
                elapsed_ms: Joi.integer(gte: 1, lte: 3_600_000) |> Joi.default(120_000),
                input_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.default(nil),
                output_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.default(nil),
                total_tokens: Joi.integer(gte: 1) |> Joi.nullable() |> Joi.default(nil),
                total_cost: Joi.number(gte: 0) |> Joi.nullable() |> Joi.default(nil),
                output_chars: Joi.integer(gte: 1, lte: 1_000_000) |> Joi.default(32_000)
              },
              unrecognized_keys: :error
            )
            |> Joi.default(%{
              elapsed_ms: 120_000,
              input_tokens: nil,
              output_tokens: nil,
              total_tokens: nil,
              total_cost: nil,
              output_chars: 32_000
            })
        },
        unrecognized_keys: :error
      ),
    output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})

  @doc "Returns the default Chain of Thought instructions."
  @spec default_instructions() :: String.t()
  def default_instructions, do: @default_instructions

  flow do
    step "start_request",
      action: StartRequest,
      params: %{
        flow: %{id: "jido.ai/reasoning/chain-of-thought", vsn: 1},
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        fallback_models: [],
        options: input(:options),
        output_schema: %{
          "type" => "object",
          "properties" => %{
            "steps" => %{
              "type" => "array",
              "minItems" => 1,
              "items" => %{
                "type" => "object",
                "properties" => %{
                  "number" => %{"type" => "integer"},
                  "content" => %{"type" => "string", "minLength" => 1}
                },
                "required" => ["number", "content"],
                "additionalProperties" => false
              }
            },
            "conclusion" => %{"type" => "string", "minLength" => 1}
          },
          "required" => ["steps", "conclusion"],
          "additionalProperties" => false
        },
        prompt_cache: input(:prompt_cache),
        context_window: input(:context),
        max_model_calls: 1,
        max_retries: 0,
        max_elapsed_ms: input([:limits, :elapsed_ms]),
        max_input_tokens: input([:limits, :input_tokens]),
        max_output_tokens: input([:limits, :output_tokens]),
        max_total_tokens: input([:limits, :total_tokens]),
        max_total_cost: input([:limits, :total_cost]),
        max_output_chars: input([:limits, :output_chars])
      }

    step "input_guard",
      action: GuardInput,
      params: %{turn: result("start_request")}

    invoke "reason",
      decision: DecideInput,
      expander: ExpandDecision,
      params: %{
        turn: result("start_request"),
        guard: result("input_guard"),
        target: value(Jido.AI.Reasoning.ChainOfThought.ModelRound)
      }

    step "finalize",
      action: FinalizeTurn,
      params: %{outcome: result("reason")}

    output result("finalize")
  end
end
