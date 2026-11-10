# Thread Projection

`Jido.AI.Thread.Projection` decides which Thread entries become model messages. This guide explains the rules, shows how to ask why a message was left out, and shows how to size the history window. Read it when the model does not see something you expected, or sees too much.

## What can enter a model request

The Thread stores everything a request did. A projection selects from it in four steps:

1. Keep `:ai_message` entries. Observations such as `:ai_model_attempt`, `:ai_tool_attempt`, `:ai_review`, and `:ai_request_outcome` never reach a model.
2. Drop messages whose request ended without `:completed`. A message with a `run_id` is matched to that run's `:ai_request_outcome` entry. A run with no outcome yet stays eligible, which is how the current request sees its own messages.
3. Drop incomplete tool exchanges. An assistant tool request stays only when every tool call has one matching tool result.
4. Keep whole conversation turns, newest first, until the next older turn would exceed the window.

A turn starts at a user message. The newest turn is always kept, even when it alone is over the limit. The stored Thread does not change.

## Build a Session by hand

`Jido.AI.Thread.Projection.append/4` adds a message. `Jido.AI.Thread.Projection.observe/5` adds an observation. Reasoning Flows call these for you, and you can call them to seed history.

```elixir
alias Jido.AI.Thread.Projection

session = Jido.Session.new(id: "session:order-5512", now: 1_000)
completed = %{run_id: "run-1", request_id: "request-1"}
blocked = %{run_id: "run-2", request_id: "request-2"}

{:ok, session} = Projection.append(session, %{role: :user, content: "Where is order 5512?"}, completed, 1_001)
{:ok, session} = Projection.append(session, %{role: :assistant, content: "It ships Friday."}, completed, 1_002)
session = Projection.observe(session, :ai_request_outcome, %{status: :completed}, completed, 1_003)

{:ok, session} = Projection.append(session, %{role: :user, content: "Cancel every order."}, blocked, 1_004)
session = Projection.observe(session, :ai_request_outcome, %{status: :blocked}, blocked, 1_005)

{:ok, messages} = Projection.messages(session)

[%{role: :user, content: "Where is order 5512?"}, %{role: :assistant, content: "It ships Friday."}] =
  Enum.map(messages, &Map.take(&1, [:role, :content]))

5 = session.thread.rev
```

The Thread has 5 entries. The projection has 2 messages.

## Ask why a message was excluded

`Jido.AI.Thread.Projection.explain/2` returns a decision for each message entry.

```elixir
alias Jido.AI.Thread.Projection

{:ok, explanation} = Projection.explain(session, %{})

[
  %{seq: 0, state: :included, reason: :projected},
  %{seq: 1, state: :included, reason: :projected},
  %{seq: 3, state: :excluded, reason: :request_not_completed}
] = Enum.map(explanation.decisions, &Map.take(&1, [:seq, :state, :reason]))
```

The reasons are:

| Reason | Meaning |
| --- | --- |
| `:projected` | The message is in the projection. |
| `:request_not_completed` | Its run ended `:blocked` or `:failed`. |
| `:incomplete_tool_exchange` | A tool call has no result, or a tool result has no call. |
| `:outside_context_window` | An older turn did not fit the window. |

## Size the window

The `context` field on a request sets `max_messages` and `max_bytes`. Both count whole turns.

```elixir
alias Jido.AI.Thread.Projection

history =
  Enum.reduce(1..3, Jido.Session.new(id: "session:window", now: 2_000), fn number, current ->
    {:ok, current} = Projection.append(current, %{role: :user, content: "Question #{number}"})
    {:ok, current} = Projection.append(current, %{role: :assistant, content: "Answer #{number}"})
    current
  end)

{:ok, window} = Projection.project(history, %{max_messages: 4})

%{
  available_messages: 6,
  included_messages: 4,
  dropped_messages: 2,
  first_seq: 2,
  last_seq: 5
} = Map.drop(window, [:messages])

{:ok, oversized} = Projection.project(history, %{max_messages: 1})
2 = oversized.included_messages
```

The last call shows the guarantee for the newest turn. A limit of 1 still returns its 2 messages.

The ReAct defaults are 64 messages and 200,000 bytes. Set them on the Agent or per request:

<!-- partial -->
```elixir
ai do
  reasoning Jido.AI.Reasoning.ReAct do
    context do
      max_messages 16
      max_bytes 40_000
    end
  end
end
```

## Watch an incomplete tool exchange drop out

Each tool call needs a result with its `tool_call_id` before the assistant message can enter a request.

```elixir
alias Jido.AI.Thread.Projection

call = %{id: "call-1", name: "lookup_order", arguments: %{order_id: "5512"}}

open_session = Jido.Session.new(id: "session:tools", now: 3_000)
{:ok, open_session} = Projection.append(open_session, %{role: :user, content: "Check it."})

{:ok, open_session} =
  Projection.append(open_session, %{role: :assistant, content: "", tool_calls: [call]})

{:ok, open_messages} = Projection.messages(open_session)
[:user] = Enum.map(open_messages, & &1.role)

{:ok, closed_session} =
  Projection.append(open_session, %{
    role: :tool,
    name: "lookup_order",
    tool_call_id: "call-1",
    content: "",
    output: %{"status" => "packed"}
  })

{:ok, closed_messages} = Projection.messages(closed_session)
[:user, :assistant, :tool] = Enum.map(closed_messages, & &1.role)
```

## Get the ReqLLM context

`Jido.AI.Thread.Projection.context/2` returns the same data with a validated `ReqLLM.Context` under `:context`. `Jido.AI.Reasoning.Actions.ProjectConversation` uses it. Each message carries its source in `metadata.jido.source`, so you can trace a prompt message back to its entry. This function does not add instructions. The Action adds them when it opens the [model context](model-context-lifecycle.md).

```elixir
alias Jido.AI.Thread.Projection

{:ok, %{context: context}} = Projection.context(closed_session, %{})

messages = ReqLLM.Context.to_list(context)
[:user, :assistant, :tool] = Enum.map(messages, & &1.role)

%{type: :thread_entry, seq: 0} = hd(messages).metadata.jido.source
```

`Jido.AI.Thread.Projection.breakpoint/1` returns the `seq` of the last entry a projection can include, or `nil` when there is none.

```elixir
alias Jido.AI.Thread.Projection

2 = Projection.breakpoint(closed_session)
nil = Projection.breakpoint(Jido.Session.new(id: "session:empty"))
```

## Related

- [AI Requests and Sessions](requests-responses-and-sessions.livemd)
- [Model Context Lifecycle](model-context-lifecycle.md)
- [Sessions and Threads](../data/sessions-and-threads.md)
