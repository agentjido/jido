# Model Context Lifecycle

`Jido.AI.Context` wraps the exact data of one ReqLLM call as it moves from open to prepared to completed. This guide explains each stage and how to read the record it leaves. The context here is the model call's messages and tools. It is separate from the Action context map.

## The three stages

A built-in reasoning Flow creates one `Jido.AI.Context` for each model call:

| Stage | Set by | What it allows |
| --- | --- | --- |
| `:open` | `Jido.AI.Context.new/2` | `Jido.AI.Context.transform/3` can change the messages and tools. |
| `:prepared` | `Jido.AI.Context.prepare/2` | The model, context, and options are frozen, and a digest of them is stored. |
| `:completed` | `Jido.AI.Context.complete/3` | The ReqLLM result is attached. Nothing can change after this. |

In a ReAct model round, `Jido.AI.Reasoning.Actions.ProjectConversation` opens the context from the Thread. It puts the instructions first and any repair instruction last. `Jido.AI.Reasoning.Actions.CallModel` then adds the tools, prepares, calls the inference client with the prepared request, and completes the context. The context is rebuilt for every model call and is not stored.

## Walk through a call

The module has no process and does not know about Threads, tools, or reasoning. You can drive it with a plain `ReqLLM.Context`.

```elixir
alias Jido.AI.Context

messages =
  ReqLLM.Context.new([
    ReqLLM.Context.system("Answer shipping questions."),
    ReqLLM.Context.user("Where is order 5512?")
  ])

{:ok, open} = Context.new(messages, metadata: %{order_id: "5512"})

:open = open.stage
```

`Jido.AI.Context.transform/3` changes the open context. Its operation ID makes the change idempotent, so a repeat with the same ID returns the context without running the function.

```elixir
alias Jido.AI.Context

add_note = fn req_llm_context ->
  note = ReqLLM.Context.system("The carrier reports a one-day delay.")
  %{req_llm_context | messages: req_llm_context.messages ++ [note]}
end

{:ok, transformed} = Context.transform(open, "carrier-note:1", add_note)
{:ok, ^transformed} = Context.transform(transformed, "carrier-note:1", add_note)

3 = length(transformed.request.context.messages)
```

`Jido.AI.Context.prepare/2` requires a model and freezes the request. A later transform returns an error.

```elixir
alias Jido.AI.Context

{:ok, prepared} =
  Context.prepare(transformed, model: "openai:gpt-4o-mini", options: [temperature: 0.0])

:prepared = prepared.stage
{:error, :context_not_open} = Context.transform(prepared, "late", & &1)

true = is_binary(prepared.digest)
```

`Jido.AI.Context.complete/3` attaches `{:ok, %ReqLLM.Response{}}` or `{:error, reason}`. The request does not change.

```elixir
alias Jido.AI.Context

assistant = ReqLLM.Context.assistant("Order 5512 arrives one day late.")

response = %ReqLLM.Response{
  id: "local",
  model: "openai:gpt-4o-mini",
  context: ReqLLM.Context.append(prepared.request.context, assistant),
  message: assistant,
  finish_reason: :stop,
  usage: %{input_tokens: 12, output_tokens: 7}
}

{:ok, completed} = Context.complete(prepared, {:ok, response})

:completed = completed.stage
{:error, :context_already_completed} = Context.complete(completed, {:error, :timeout})
```

Calling `complete/3` on an open context returns `{:error, :context_not_prepared}`.

## Inspect with snapshots

`Jido.AI.Context.Snapshot` turns a stage into a portable record. Its `:content` option sets how much message content the record holds:

| `:content` | Messages | Use |
| --- | --- | --- |
| `:none` | Digests and shape only | Long-lived records. |
| `:redacted` (default) | `"[REDACTED]"` placeholders | Logs. |
| `:full` | The full text | Local debugging. |

`new/2` on `Jido.AI.Context.Snapshot` is marked `@doc false`, but no other public function builds a snapshot, so the example below uses it. `Jido.AI.Context.Snapshot.diff/2`, `Jido.AI.Context.Snapshot.encode/1`, and `Jido.AI.Context.Snapshot.decode/1` work on what it returns.

```elixir
alias Jido.AI.Context.Snapshot

before_change = Snapshot.new(open, content: :full)
after_change = Snapshot.new(prepared, content: :full)

%{
  request_changed: true,
  messages_changed: true,
  message_count: %{before: 2, after: 3},
  before: %{stage: :open},
  after: %{stage: :prepared}
} = Snapshot.diff(before_change, after_change)

summary = Snapshot.new(completed, content: :none)

%{message_count: 3, tool_count: 0, roles: %{system: 2, user: 1}} = summary.shape

{:ok, %{"type" => "jido.ai.context.snapshot", "stage" => "completed"}} =
  summary |> Snapshot.encode() |> Snapshot.decode()
```

Snapshots replace the values of sensitive option names, such as `api_key`, `password`, or any name that ends in `_secret`, with `"[REDACTED]"`. This applies at every content level.

## Read what a request recorded

`Jido.AI.Reasoning.Actions.RecordModelAttempt` stores two `:none` snapshots as JSON on each model attempt: `context.before` from the prepared stage and `context.after` from the completed stage. Find them on `model_attempts` in the reply or on `:ai_model_attempt` entries in the Thread. They let you compare the requests of two attempts by digest and see message counts without storing a second copy of the prompt.

Run any AI request and decode them:

```elixir
alias Jido.AI.Context.Snapshot

defmodule ContextGuide.LocalModel do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, _options) do
    {:ok,
     %ReqLLM.Response{
       id: "local",
       model: model,
       context: context,
       message: ReqLLM.Context.assistant("It ships Friday."),
       finish_reason: :stop,
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

defmodule ContextGuide.ShippingAgent do
  use Jido.AI.Agent, name: "shipping_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct
  end
end

agent = ContextGuide.ShippingAgent.instantiate!(id: "shipping-1")

{:ok, _agent, [%{signal: reply}]} =
  ContextGuide.ShippingAgent.cmd(
    agent,
    ContextGuide.ShippingAgent.request_signal!(%{input: "When does it ship?"}),
    context: %{jido_ai_inference_client: ContextGuide.LocalModel}
  )

%{context: %{format: "jido.ai.context.snapshot+json", before: before_json, after: after_json}} =
  hd(reply.data.model_attempts)

prepared_record = Snapshot.decode!(before_json)
completed_record = Snapshot.decode!(after_json)

{"prepared", "completed"} = {prepared_record["stage"], completed_record["stage"]}
%{"roles" => %{"system" => 1, "user" => 1}} = prepared_record["shape"]
true = prepared_record["digest"] == completed_record["digest"]
```

The digest stays the same across the two stages because `complete/3` does not change the request.

## Related

- [Thread Projection](thread-projection.md) decides which messages open a context.
- [Inference Clients](inference-clients.md) receive the prepared request.
- [Tool Calls and Results](tool-calls-and-results.md) add tool messages to the next context.
