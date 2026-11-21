# Tool Calls and Results

This guide follows one tool call in `Jido.AI.Reasoning.ReAct` from the model's request to the result the model reads next. It covers validation, parallel execution, error handling, and the size limit on results. Read [Tools and Toolsets](tools-skills-and-toolsets.livemd) first for how to declare tools.

## The path of a tool call

1. The model returns a response with tool calls.
2. `Jido.AI.Reasoning.Actions.GuardOutput` validates the whole batch. A bad batch runs no tools.
3. If any call needs review, the Flow waits for approval.
4. A Flow Parallel component runs each call as its own node. Results are joined in the order of the calls.
5. `Jido.AI.Reasoning.ReAct.Actions.RecordToolResults` converts each result, then appends a `:ai_tool_attempt` entry and a `:tool` message to the Thread.
6. The next model call sees the tool messages.

## Set up an example

The local client plays a script of responses, one per model call. It stores each context it receives, so the examples can read what the model saw.

```elixir
defmodule ToolCallsGuide.Script do
  @behaviour Jido.AI.InferenceClient

  def play(responses) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = Agent.start_link(fn -> %{next: responses, seen: []} end, name: __MODULE__)
  end

  def seen, do: Agent.get(__MODULE__, &Enum.reverse(&1.seen))

  @impl true
  def generate_text(model, context, _options) do
    messages = ReqLLM.Context.to_list(context)

    step =
      Agent.get_and_update(__MODULE__, fn %{next: [step | rest], seen: seen} ->
        {step, %{next: rest, seen: [messages | seen]}}
      end)

    message =
      case step do
        {:tools, calls} ->
          ReqLLM.Context.assistant(
            "",
            tool_calls:
              Enum.map(calls, fn {id, name, arguments} ->
                ReqLLM.ToolCall.new(id, name, JSON.encode!(arguments))
              end)
          )

        text when is_binary(text) ->
          ReqLLM.Context.assistant(text)
      end

    {:ok,
     %ReqLLM.Response{
       id: "local",
       model: model,
       context: context,
       message: message,
       finish_reason: if(is_binary(step), do: :stop, else: :tool_calls),
       usage: %{input_tokens: 4, output_tokens: 3}
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

defmodule ToolCallsGuide.CheckStock do
  use Jido.Action,
    name: "check_stock",
    description: "Check stock for one product",
    schema: Jido.Joi.object(%{sku: Jido.Joi.string()})

  @impl true
  def run(%{sku: "MISSING"}, _context), do: {:error, Jido.Error.execution_error("warehouse is offline")}
  def run(%{sku: "HUGE"}, _context), do: {:ok, %{notes: String.duplicate("x", 2_000)}}
  def run(%{sku: "CLOCK"}, _context), do: {:ok, %{checked_at: self()}}
  def run(%{sku: sku}, _context), do: {:ok, %{sku: sku, on_hand: 12}}
end

defmodule ToolCallsGuide.StockAgent do
  use Jido.AI.Agent, name: "stock_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      limits do
        retries 0
        tool_output_bytes 512
      end
    end

    tools do
      action ToolCallsGuide.CheckStock
    end
  end
end

defmodule ToolCallsGuide do
  def ask(responses, input \\ "Check stock.") do
    ToolCallsGuide.Script.play(responses)
    agent = ToolCallsGuide.StockAgent.instantiate!(id: "stock-#{System.unique_integer([:positive])}")

    {:ok, _agent, [%{signal: reply}]} =
      ToolCallsGuide.StockAgent.cmd(
        agent,
        ToolCallsGuide.StockAgent.request_signal!(%{input: input}),
        context: %{jido_ai_inference_client: ToolCallsGuide.Script}
      )

    reply.data
  end
end
```

## Parallel calls and ordered results

One response can request up to 4 tool calls. All of them run in one tool round, and results return in call order.

```elixir
reply =
  ToolCallsGuide.ask([
    {:tools,
     [
       {"call-a", "check_stock", %{sku: "A-1"}},
       {"call-b", "check_stock", %{sku: "B-2"}}
     ]},
    "Both are in stock."
  ])

%{status: :completed, tool_rounds: 1, tool_calls: 2, tool_errors: 0} = reply

[
  %{tool_call_id: "call-a", status: :ok, output: %{"sku" => "A-1", "on_hand" => 12}, tool_round: 1},
  %{tool_call_id: "call-b", status: :ok, output: %{"sku" => "B-2", "on_hand" => 12}, tool_round: 1}
] = reply.tool_attempts

[_system, _user, _assistant, first_result, second_result] = List.last(ToolCallsGuide.Script.seen())

{:tool, "call-a", %{"sku" => "A-1", "on_hand" => 12}} =
  {first_result.role, first_result.tool_call_id, first_result.metadata.tool_output}

"call-b" = second_result.tool_call_id
```

Each attempt also has `input`, `tool`, `error`, `content`, `metadata`, `result_metadata`, `started_at_ms`, `completed_at_ms`, `duration_ms`, `effects_count`, and `review`. The model sees only the projected output.

## Calls the guard rejects

`Jido.AI.Reasoning.Actions.GuardOutput` rejects the whole response for any of these reasons. The Flow then asks the model to repair its response, within `limits.retries`.

| Reason | Cause |
| --- | --- |
| `one model response can contain at most 4 tool calls` | More than 4 calls. This limit is fixed. |
| `tool call IDs must be unique` | Two calls share an ID. |
| `model requested a tool that is not allowed` | The name is not in the selected tools. |
| `invalid tool call: ...` | The arguments fail the tool's schema. |
| `model requested a tool round without tool calls` | The response has a tool-call kind and no calls. |

With `retries` at 0, the first rejection ends the request. The attempted call never runs.

```elixir
reply = ToolCallsGuide.ask([{:tools, [{"call-a", "delete_stock", %{sku: "A-1"}}]}])

%{
  status: :blocked,
  reason_code: :output,
  reason: "model requested a tool that is not allowed",
  tool_calls: 0,
  tool_attempts: []
} = reply
```

The tool-call counters in `limits` are separate from this guard. When a valid response would pass `tool_calls` or start a round past `tool_rounds`, the request ends with reason code `:limits`.

## Tool errors go to the model

A tool that returns an error does not fail the request. The model receives a safe error and can react. Only `type`, `message`, and `retryable` reach it.

```elixir
reply =
  ToolCallsGuide.ask([
    {:tools, [{"call-a", "check_stock", %{sku: "MISSING"}}]},
    "The warehouse is offline."
  ])

%{status: :completed, output: "The warehouse is offline.", tool_errors: 1} = reply
[%{status: :error, error: %{"message" => message, "retryable" => retryable}}] = reply.tool_attempts
true = is_binary(message) and is_boolean(retryable)

tool_message = ToolCallsGuide.Script.seen() |> List.last() |> List.last()
%{"status" => "error", "error" => %{"message" => ^message}} = tool_message.metadata.tool_output
```

Messages are limited to 1,024 bytes and types to 128 bytes. To keep details from the model, put them in telemetry or logs and return a plain message from the Action.

## The size limit on results

`limits.tool_output_bytes` caps the JSON size of each result the model sees. It defaults to 16,384 bytes. A larger result is replaced by a notice, not cut in the middle, because partial JSON would mislead the model.

```elixir
reply =
  ToolCallsGuide.ask([
    {:tools, [{"call-a", "check_stock", %{sku: "HUGE"}}]},
    "The notes were too long to read."
  ])

[attempt] = reply.tool_attempts

%{
  "status" => "truncated",
  "message" => "tool result exceeded the model-content limit",
  "max_bytes" => 512
} = attempt.output

%{truncated: true, max_bytes: 512} = attempt.metadata
```

The attempt stores the same notice, not the original value, so the Thread stays bounded too. Have the tool return a reference or a summary when its data is large.

## Results that are not JSON

`Jido.AI.ToolResult.project/2` encodes a result as JSON. A value that JSON cannot encode, such as a PID, becomes an error notice.

```elixir
reply =
  ToolCallsGuide.ask([
    {:tools, [{"call-a", "check_stock", %{sku: "CLOCK"}}]},
    "The tool result was invalid."
  ])

[%{output: %{"status" => "error", "error" => %{"type" => "invalid_tool_result"}}}] = reply.tool_attempts
```

The function also works alone, and it shows the conversion on any value:

```elixir
{%{"on_hand" => 12}, %{bytes: 14, max_bytes: 256, truncated: false}} =
  Jido.AI.ToolResult.project(%{on_hand: 12}, 256)
```

## Return content parts

Return a `ReqLLM.ToolResult` when a tool produces text or media for the model. `output` is the structured value, `content` holds the parts, and `metadata` stays with the result. The size limit covers all three together.

```elixir
result = %ReqLLM.ToolResult{
  content: [ReqLLM.Message.ContentPart.text("Stock chart is attached.")],
  output: %{chart_id: "chart-9"},
  metadata: %{source: "reporting"}
}

normalized = Jido.AI.ToolResult.normalize(%{status: :ok, value: result}, 1_024)

%{
  status: :ok,
  model_content: %{"chart_id" => "chart-9"},
  result_metadata: %{"source" => "reporting"},
  metadata: %{truncated: false, content_parts: 1},
  content_parts: [%{"type" => "text", "text" => "Stock chart is attached."}]
} = normalized
```

## Effects from tools

A tool Action can return `{:ok, value, effects}`. The tool attempt counts them in `effects_count`. Read [Action Effects](../actions/action-effects.livemd) for what effects are.

## Related

- [ReAct Reasoning](react-reasoning.livemd)
- Tool Review
- [Model Budgets and Usage](budgets-and-usage.md)
