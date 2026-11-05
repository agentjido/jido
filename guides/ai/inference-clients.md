# Inference Clients

`Jido.AI.InferenceClient` is the boundary between Jido AI and whatever serves model calls. This guide shows how a client is selected and how to write your own, for tests, a gateway, or a provider ReqLLM does not reach.

## How a client is selected

`Jido.AI.InferenceClient.Selection.client!/1` picks a client for each operation in this order:

1. The `:jido_ai_inference_client` key in the Action context.
2. The `:ai_inference_client` key in the `:jido` application environment.
3. `Jido.AI.InferenceClient.ReqLLM`, which forwards each call to the matching `ReqLLM` function.

<!-- partial -->
```elixir
# config/test.exs
config :jido, ai_inference_client: MyApp.LocalModel
```

The context key applies to one call, so tests can use it with `async: true`:

<!-- partial -->
```elixir
MyApp.SupportAgent.cmd(agent, request, context: %{jido_ai_inference_client: MyApp.LocalModel})

Jido.AgentServer.call(server, request, timeout: 30_000, context: %{jido_ai_inference_client: MyApp.LocalModel})
```

## Write a client

A client must export all 22 callbacks. Selection checks this each time, even when the Flow uses only one of them. `Jido.AI.Reasoning.ReAct` and the other built-in reasoning Flows call `generate_text/3`, or `stream_text/3` when the request sets `stream: true`. `Jido.AI.Actions.Embed` calls `embed/3`. Nothing else in Jido calls the rest.

This client returns a fixed reply and returns `{:error, :not_supported}` for what it does not serve:

```elixir
defmodule InferenceGuide.CannedReplies do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, options) do
    {:ok,
     %ReqLLM.Response{
       id: "canned-1",
       model: model,
       context: context,
       message: ReqLLM.Context.assistant("Temperature was #{inspect(options[:temperature])}."),
       finish_reason: :stop,
       usage: %{input_tokens: 8, output_tokens: 4}
     }}
  end

  @impl true
  def embed(_model, input, _options) do
    vectors = input |> List.wrap() |> Enum.map(&[String.length(&1) * 1.0])
    {:ok, %{embedding: vectors, usage: %{input_tokens: length(vectors)}}}
  end

  @impl true
  def evaluation_models, do: []

  @handled [generate_text: 3, embed: 3, evaluation_models: 0]

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks), {name, arity} not in @handled do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
      do: {:error, :not_supported}
  end
end

defmodule InferenceGuide.Agent do
  use Jido.AI.Agent, name: "inference_guide_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      options %{temperature: 0.1}
    end
  end
end

agent = InferenceGuide.Agent.instantiate!(id: "inference-1")

{:ok, _agent, [%{signal: reply}]} =
  InferenceGuide.Agent.cmd(
    agent,
    InferenceGuide.Agent.request_signal!(%{input: "Hello"}),
    context: %{jido_ai_inference_client: InferenceGuide.CannedReplies}
  )

%{status: :completed, output: "Temperature was 0.1."} = reply.data
```

The `generate_text/3` arguments are the model string, a `ReqLLM.Context`, and a keyword list of options. Read [Configure ReqLLM](req-llm-configuration.livemd) for what the options contain.

## What a response must contain

For `generate_text/3`, return `{:ok, %ReqLLM.Response{}}` with these fields:

| Field | Purpose |
| --- | --- |
| `:id`, `:model`, `:context` | Identify the call. They are recorded on the model attempt. |
| `:message` | An assistant message from `ReqLLM.Context.assistant/2`. Pass `tool_calls:` to request tools. |
| `:finish_reason` | `:stop` or `:tool_calls` proceed. Other values fail the output guard. |
| `:usage` | Input and output token counts, plus any cost facts. Use `nil` when the source has none. |
| `:object` | The decoded structured output, as a map with string keys, when the request has an `output_schema`. |

A `{:error, reason}` return does not raise. It becomes a model attempt with `status: :error`, and [ReAct](react-reasoning.livemd) decides whether to retry. These reasons are retryable: ReqLLM timeout errors, ReqLLM request errors with status 408, 409, 425, 429, 500, 502, 503, or 504, the transport atoms such as `:timeout` and `:closed`, and any reason whose inspected text contains `timeout`, `overload`, `rate_limit`, `rate limit`, `unavailable`, or `closed`.

## Serve embeddings

`Jido.AI.Actions.Embed` is an ordinary Action. It defaults to the model `"openai:text-embedding-3-small"`, passes `return_usage: true`, and expects `embedding` and `usage` keys from `embed/3`.

```elixir
{:ok, %{embedding: [[6.0], [5.0]], usage: %{input_tokens: 2}}} =
  Jido.Exec.run(
    Jido.AI.Actions.Embed,
    %{input: ["refund", "order"]},
    %{jido_ai_inference_client: InferenceGuide.CannedReplies}
  )
```

Run it as a route target or a Flow step, the same as any other Action.

## Invalid clients

A client that is not loaded, or that lacks a callback, raises `ArgumentError` in `Jido.AI.InferenceClient.Selection.client!/1` with `"invalid Jido AI inference client: ..."`. Inside an Agent turn, the model call records this as a model error that cannot be retried. `cmd/3` returns a reply with `status: :failed`, the same shape as any other model error, and the reason holds the message.

```elixir
true = Jido.AI.InferenceClient.Selection.client!(%{jido_ai_inference_client: InferenceGuide.CannedReplies}) == InferenceGuide.CannedReplies

"invalid Jido AI inference client: InferenceGuide.Missing" =
  try do
    Jido.AI.InferenceClient.Selection.client!(%{jido_ai_inference_client: InferenceGuide.Missing})
  rescue
    error in ArgumentError -> error.message
  end

{:ok, _agent, [%{signal: failed}]} =
  InferenceGuide.Agent.cmd(
    agent,
    InferenceGuide.Agent.request_signal!(%{input: "Hello"}),
    context: %{jido_ai_inference_client: InferenceGuide.Missing}
  )

%{status: :failed, reason: "invalid Jido AI inference client: InferenceGuide.Missing"} = failed.data
```

## Related

- [Configure ReqLLM](req-llm-configuration.livemd) configures the default client.
- [Model Capabilities](model-capabilities.md) lists what each callback serves.
- [Test AI Agents](testing-ai-agents.livemd) uses a local client in ExUnit.
