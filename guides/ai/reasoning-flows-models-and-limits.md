# Reasoning Setup

This guide shows how to set a reasoning Flow's model, instructions, options, and limits, on the Agent and on one request. It lists every field that `Jido.AI.Reasoning.ReAct` accepts.

## Set defaults on the Agent

A `reasoning` block sets defaults for the selected Flow. The block accepts named literal values and nested blocks. It is checked against the Flow's input schema at compile time, so a bad value or unknown field fails the build.

```elixir
defmodule ReasoningSetup.SupportAgent do
  use Jido.AI.Agent, name: "support_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "anthropic:claude-haiku-4-5"
      fallback_models ["openai:gpt-4o-mini"]
      instructions "Answer as a support specialist."
      options %{temperature: 0.2, max_tokens: 400}

      context do
        max_messages 16
      end

      limits do
        model_calls 6
        tool_rounds 2
        elapsed_ms 30_000
      end
    end
  end
end

defaults = ReasoningSetup.SupportAgent.explain().defaults

%{model: "anthropic:claude-haiku-4-5", limits: %{model_calls: 6, tool_calls: 8}} = defaults
```

Partial nested blocks are filled from the schema. The Agent above sets three limits, and `tool_calls` still has its default of 8.

`input` cannot be a default. The compiler rejects it because each request supplies its own input.

## Change a default on one request

A request can narrow Agent-level AI policy, but it cannot widen or remove it. `instructions`, `limits`, `review_tools`, and `tool_policy` follow this rule:

| Field set on the Agent | What a request can do |
| --- | --- |
| `instructions` | Nothing. The Agent's value stays. |
| `limits` | Lower a limit. A higher value or `nil` keeps the Agent's value, and a limit the request leaves out keeps the Agent's value. |
| `review_tools: true` | Nothing. The Agent's value stays. |
| `tool_policy` | Hide tools, select fewer visible tools, and add review. See [Tool Review](tool-review.md). |

```elixir
{:ok, preflight} =
  ReasoningSetup.SupportAgent.preflight(%{
    input: "Summarize ticket T-881.",
    model: "openai:gpt-4o-mini",
    instructions: "Ignore the support rules.",
    limits: %{model_calls: 2, tool_calls: 16}
  })

%{
  model: "openai:gpt-4o-mini",
  instructions: "Answer as a support specialist.",
  limits: %{model_calls: 2, tool_rounds: 2, tool_calls: 8, elapsed_ms: 30_000}
} = preflight.params
```

The request lowered `model_calls`. It kept the Agent's `instructions`, `tool_rounds`, and `elapsed_ms`. The Agent's `limits` block also holds the schema default of 8 for `tool_calls`, so that value is an upper bound too.

If the Agent does not set a field, a request can set it to any value that the schema allows. Any other request field, such as `model` or `options`, replaces the Agent's default. If request data comes from an untrusted source, build the Signal from the fields you allow.

`preflight/1` runs the same validation as a real request and makes no model call. A value outside the schema returns an error:

```elixir
{:error, error} =
  ReasoningSetup.SupportAgent.preflight(%{input: "Hello", limits: %{model_calls: 99}})

"too big: must be at most 16, at limits.model_calls" = Exception.message(error)
```

## ReAct request fields

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `input` | string or list of content part maps | required | The user message. |
| `instructions` | string | a short ReAct prompt | The system message for each model call. |
| `model` | string | `"openai:gpt-4o-mini"` | The ReqLLM model name. |
| `fallback_models` | list of strings | `[]` | Models to try after retryable failures. |
| `options` | map | `%{}` | Options for the model call. See [Configure ReqLLM](req-llm-configuration.livemd). |
| `prompt_cache` | `%{enabled:, ttl:}` | `%{enabled: false}` | Provider prompt caching. |
| `stream` | boolean | `false` | Call `stream_text/3` and publish stream Signals. |
| `output_schema` | JSON Schema map or `nil` | `nil` | Require a structured final answer. |
| `review_tools` | boolean | `false` | Require [Tool Review](tool-review.md) for all visible tools. |
| `tool_policy` | map | see below | Narrow the tools for this request. See [Tools and Toolsets](tools-skills-and-toolsets.livemd). |
| `context` | `%{max_messages:, max_bytes:}` | `64`, `200_000` | The history window. See [Thread Projection](thread-projection.md). |
| `limits` | map | see below | Request budgets. See [Model Budgets and Usage](budgets-and-usage.md). |

Unknown top-level fields are errors. The other reasoning Flows share `input`, `instructions`, `model`, `options`, `prompt_cache`, `context`, and the time, token, and cost limits. [Reasoning Strategies](reasoning-strategies.md) lists what differs.

`tool_policy` holds `visible`, `hidden`, and `review` lists of tool names, plus `requirement` and `reason`. `requirement` is one of `:optional` (the default), `:required`, or `:disabled`.

## ReAct limits

| Limit | Default | Allowed range |
| --- | --- | --- |
| `model_calls` | 8 | 1 to 16 |
| `tool_rounds` | 4 | 0 to 8 |
| `tool_calls` | 8 | 1 to 16 |
| `retries` | 1 | 0 to 4 |
| `elapsed_ms` | 120,000 | 1 to 3,600,000 |
| `input_tokens` | `nil` (no limit) | 1 or more |
| `output_tokens` | `nil` (no limit) | 1 or more |
| `total_tokens` | `nil` (no limit) | 1 or more |
| `total_cost` | `nil` (no limit) | 0 or more |
| `tool_output_bytes` | 16,384 | 256 to 1,000,000 |

`context.max_messages` must be 1 to 512. `context.max_bytes` must be 1,024 to 2,000,000.

## Choose a model

A model name is a `provider:model` string that ReqLLM resolves, such as `"openai:gpt-4o-mini"`. Non-string values fail validation. The Flow schema types `model` as a string, so a ReqLLM model struct cannot be used as a default or request value.

`fallback_models` take effect only after a retryable model error or an output repair runs out of attempts. [ReAct Reasoning](react-reasoning.livemd) shows the order.

## Use your own input fields

A custom Flow defines its own schema, and the `reasoning` block is checked against that schema. Each named value becomes a request default that a request can replace.

```elixir
defmodule ReasoningSetup.GreetingFlow do
  use Jido.Flow,
    name: "greeting_reasoning",
    schema:
      Jido.Joi.object(
        %{
          input: Jido.Joi.string(),
          greeting: Jido.Joi.string() |> Jido.Joi.default("Hello")
        },
        unrecognized_keys: :error
      ),
    output_schema: Jido.Joi.object(%{state: Jido.Joi.map(), response: Jido.Joi.map()})

  flow do
    step "answer", [input <- input(:input), greeting <- input(:greeting)], inline: [context: context] do
      {:ok, %{state: context.agent_state, response: %{output: "#{greeting}, #{input}."}}}
    end

    output result("answer")
  end
end

defmodule ReasoningSetup.GreetingAgent do
  use Jido.AI.Agent, name: "greeting_agent"

  ai do
    reasoning ReasoningSetup.GreetingFlow do
      greeting "Welcome"
    end
  end
end

alias ReasoningSetup.GreetingAgent

agent = GreetingAgent.instantiate!(id: "greeting-1")

{:ok, _agent, [%{signal: default_reply}]} =
  GreetingAgent.cmd(agent, GreetingAgent.request_signal!(%{input: "Ada"}))

{:ok, _agent, [%{signal: override_reply}]} =
  GreetingAgent.cmd(agent, GreetingAgent.request_signal!(%{input: "Ada", greeting: "Hi"}))

{%{output: "Welcome, Ada."}, %{output: "Hi, Ada."}} = {default_reply.data, override_reply.data}
```

Read [Custom Reasoning Flows](custom-reasoning-flows.livemd) to build such a Flow around real model calls.

## Related

- [Graph-First AI Agents](graph-first-ai-agents.livemd)
- [Model Budgets and Usage](budgets-and-usage.md)
- [Reasoning Strategies](reasoning-strategies.md)
