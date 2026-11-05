# Model Budgets and Usage

This guide shows how a request's budgets stop work, and where to read the tokens, cost, and time that a request used. Set budgets with `limits`. See [Reasoning Setup](reasoning-flows-models-and-limits.md) for defaults and ranges.

## When limits are checked

`Jido.AI.Budget` checks before starting more work. It does not stop a model call that is running, except that `elapsed_ms` also sets the call's `total_timeout`. A single call can therefore pass a token or cost limit, and the next check stops the request.

| Limit | Checked | Reason text |
| --- | --- | --- |
| `model_calls` | Before each model call | `maximum model calls reached` |
| `elapsed_ms` | Before each model call and tool round | `maximum elapsed time reached` |
| `input_tokens` | Before each model call and tool round | `maximum input tokens reached` |
| `output_tokens` | Before each model call and tool round | `maximum output tokens reached` |
| `total_tokens` | Before each model call and tool round | `maximum total tokens reached` |
| `total_cost` | Before each model call and tool round | `maximum total cost reached` |
| `tool_rounds` | When the model requests a tool round | `maximum tool rounds reached` |
| `tool_calls` | When the model requests a tool round | `maximum tool calls reached` |

Each limit stops at "used >= limit" for the checked values. `tool_calls` stops when the running count plus this batch would pass the limit.

A limit ends the request with status `:blocked` and reason code `:limits`. Its messages stay in the Thread but leave later model context. See [Thread Projection](thread-projection.md).

## See a limit stop a request

This local client always asks for a tool and reports 100 input tokens and 50 output tokens per call.

```elixir
defmodule BudgetsGuide.LocalModel do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, _options) do
    call =
      ReqLLM.ToolCall.new(
        "call-#{System.unique_integer([:positive])}",
        "price_quote",
        ~s({"sku":"A-#{System.unique_integer([:positive])}"})
      )

    {:ok,
     %ReqLLM.Response{
       id: "local",
       model: model,
       context: context,
       message: ReqLLM.Context.assistant("", tool_calls: [call]),
       finish_reason: :tool_calls,
       usage: %{input_tokens: 100, output_tokens: 50, total_cost: 0.002}
     }}
  end

  @impl true
  def evaluation_models, do: []

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      {name, arity} not in [generate_text: 3, evaluation_models: 0] do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
      do: {:error, :not_supported}
  end
end

defmodule BudgetsGuide.PriceQuote do
  use Jido.Action,
    name: "price_quote",
    description: "Return a price",
    schema: Jido.Joi.object(%{sku: Jido.Joi.string()})

  @impl true
  def run(_params, _context), do: {:ok, %{cents: 100}}
end

defmodule BudgetsGuide.QuoteAgent do
  use Jido.AI.Agent, name: "quote_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action BudgetsGuide.PriceQuote
    end
  end
end

defmodule BudgetsGuide do
  def ask(limits) do
    agent = BudgetsGuide.QuoteAgent.instantiate!(id: "quote-#{System.unique_integer([:positive])}")
    request = BudgetsGuide.QuoteAgent.request_signal!(%{input: "Quote it.", limits: limits})

    {:ok, _agent, [%{signal: reply}]} =
      BudgetsGuide.QuoteAgent.cmd(agent, request,
        context: %{jido_ai_inference_client: BudgetsGuide.LocalModel}
      )

    reply.data
  end
end

%{
  status: :blocked,
  reason_code: :limits,
  reason: "maximum total tokens reached",
  model_calls: 2,
  tool_rounds: 1
} = BudgetsGuide.ask(%{total_tokens: 200})
```

The first call used 150 tokens, under the limit, so its tool round started. The second used 150 more. The check after it saw 300 tokens and stopped before another tool round. The request ended at 300 tokens with a limit of 200, which shows the overrun of up to one call.

```elixir
%{status: :blocked, reason: "maximum model calls reached", model_calls: 2} =
  BudgetsGuide.ask(%{model_calls: 2})

%{status: :blocked, reason: "maximum tool rounds reached", model_calls: 2, tool_rounds: 1} =
  BudgetsGuide.ask(%{tool_rounds: 1})

%{status: :blocked, reason: "maximum total cost reached", model_calls: 2} =
  BudgetsGuide.ask(%{total_cost: 0.003})
```

## Read usage

Each reply has totals in `usage`. `Jido.AI.Usage` adds these fields across all model calls in the request, including retries:

```elixir
%{
  usage: %{
    input_tokens: 200,
    output_tokens: 100,
    total_tokens: 300,
    total_cost: total_cost,
    cache_read_tokens: 0,
    cache_write_tokens: 0,
    reasoning_tokens: 0
  },
  model_attempts: [first, second]
} = reply = BudgetsGuide.ask(%{total_tokens: 200})

true = abs(total_cost - 0.004) < 1.0e-9

%{input_tokens: 100, output_tokens: 50} = first.outcome.usage
%{input_tokens: 100, output_tokens: 50} = second.outcome.usage

reply.usage |> Map.keys() |> Enum.sort()
```

Token values are what the provider reported through ReqLLM. Cost fields are zero unless the response reports them. A failed call adds no tokens. ReqLLM calculates cost where it has pricing data, and its cost is an estimate, not an invoice.

`input_includes_cached` is `true` or `false` when every call agrees, and `:mixed` when calls differ. Use it before you subtract cached tokens from input tokens.

You can use the function directly to combine totals, for example across several requests in one Session:

```elixir
alias Jido.AI.Usage

total =
  Usage.zero()
  |> Usage.add(%{input_tokens: 100, output_tokens: 50})
  |> Usage.add(%{input_tokens: 40, output_tokens: 10})

%{input_tokens: 140, output_tokens: 60, total_tokens: 200} = total
```

## Read the budget summary

`budget` in the reply has the elapsed time and each limit. `Jido.AI.Budget.summary/2` builds it. `Jido.AI.Budget.remaining_elapsed_ms/2` gives the time left for the next call, which is never below 1.

```elixir
turn = %{
  started_at_ms: 1_000,
  max_elapsed_ms: 500,
  model_calls: 1,
  max_model_calls: 3,
  usage: %{total_tokens: 90},
  max_total_tokens: 100
}

:ok = Jido.AI.Budget.before_model(turn, 1_100)
{:error, :elapsed_ms, "maximum elapsed time reached"} = Jido.AI.Budget.before_model(turn, 1_500)

{:error, :total_tokens, "maximum total tokens reached"} =
  Jido.AI.Budget.before_model(%{turn | usage: %{total_tokens: 100}}, 1_100)

400 = Jido.AI.Budget.remaining_elapsed_ms(turn, 1_100)
1 = Jido.AI.Budget.remaining_elapsed_ms(turn, 9_000)

%{elapsed_ms: 100, limits: %{elapsed_ms: 500, model_calls: 3, total_tokens: 100}} =
  Jido.AI.Budget.summary(turn, 1_100)
```

## Read prompt cache use

Each model attempt has a `prompt_cache` field. It reports what the provider returned for that call. It is a report, not a promise that a cache was used.

```elixir
observation =
  Jido.AI.Usage.cache_observation(
    %{enabled: true, ttl: "5m"},
    %{input_tokens: 100, output_tokens: 10, cache_read_tokens: 60, cache_write_tokens: 40},
    1_000
  )

%{
  requested: true,
  requested_ttl: "5m",
  read_tokens: 60,
  write_tokens: 40,
  writes: [%{ttl: "5m", token_count: 40, ttl_ms: 300_000, estimated_expires_at_ms: 301_000}]
} = observation
```

## Export metrics

`Jido.Telemetry.AI.metrics/0` returns `Telemetry.Metrics` definitions for Agent, reasoning, tool, and model operations. Model request, token, cache, and cost events come from ReqLLM. Hand the list to your reporter:

<!-- partial -->
```elixir
children = [
  {TelemetryMetricsPrometheus, metrics: Jido.Telemetry.AI.metrics()}
]
```

See [Metrics and OTel](../operations/metrics-and-open-telemetry.md) for the full setup.

## Related

- [Reasoning Setup](reasoning-flows-models-and-limits.md)
- [ReAct Reasoning](react-reasoning.livemd)
- [Telemetry Events](../reference/telemetry-event-reference.md)
