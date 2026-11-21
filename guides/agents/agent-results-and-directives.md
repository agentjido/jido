# State and Directives

An Action or Flow on an Agent route returns the next state and an optional list of Directives. This guide shows each return shape, each built-in Directive, and what a live Agent does with them.

## Return the next state

An Action on a default route returns the complete next state, with or without Directives:

```elixir
defmodule DirectiveGuide.CloseOrder do
  use Jido.Action,
    name: "directive_guide_close_order",
    schema: Jido.Joi.object(%{order_id: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{order_id: order_id}, %{agent_state: state}) do
    {:ok, %{state | closed: [order_id | state.closed]},
     [Jido.Agent.Directive.emit("order.closed", %{order_id: order_id})]}
  end
end

defmodule DirectiveGuide.OrderBook do
  use Jido.Agent, name: "order_book"

  alias Jido.Agent.Directive

  state do
    schema Jido.Joi.object(%{
             closed: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([]),
             sent: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/orders/book"

    route "order.close", DirectiveGuide.CloseOrder, as: :close

    route "order.closed" do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | sent: context.agent_state.sent + 1}}
      end
    end

    # Partial state fails complete validation.
    route "order.partial" do
      action _input, schema: Jido.Joi.object(%{}), context: _context do
        {:ok, %{closed: []}}
      end
    end

    # The output must be a plain Map.
    route "order.not_a_map" do
      action _input, schema: Jido.Joi.object(%{}), context: _context do
        {:ok, [:not, :a, :map]}
      end
    end

    route "order.archive" do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        notice = Jido.Signal.new!("order.archived", %{}, source: "/orders/book")
        {:ok, context.agent_state, [emit(notice), Directive.server_stop(:normal)]}
      end
    end
  end
end

book = DirectiveGuide.OrderBook.instantiate!(id: "book-1")

{:ok, closed, [%Jido.Agent.Directive.Emit{signal: notice}]} =
  DirectiveGuide.OrderBook.cmd(book, DirectiveGuide.OrderBook.close_signal!(%{order_id: "o-1"}))

{["o-1"], "order.closed", "/orders/book"} = {closed.state.closed, notice.type, notice.source}
```

To return only part of a larger output, select it with `state from: output(...)` on the route. See [Routes and Handlers](build-agent-routes.livemd).

The output must be a plain Map, and it must satisfy the whole schema. Jido adds no defaults during a Turn, so a dropped field fails.

```elixir
partial = Jido.Signal.new!("order.partial", %{}, source: "/orders/api")

{:error, %Jido.Error.ValidationError{code: :incomplete_state, path: [:state]}} =
  DirectiveGuide.OrderBook.cmd(book, partial)

not_a_map = Jido.Signal.new!("order.not_a_map", %{}, source: "/orders/api")
{:error, _not_a_plain_map} = DirectiveGuide.OrderBook.cmd(book, not_a_map)
```

A Flow returns the same shape. It keeps the Directives from every successful component. A failed Flow returns no batch.

## Built-in Directives

Each Directive is a struct with a constructor on `Jido.Agent.Directive`. The Agent DSL imports `emit/1` and `emit/2`.

| Constructor | Struct | Runtime effect after commit |
| --- | --- | --- |
| `Jido.Agent.Directive.emit/2` | `Jido.Agent.Directive.Emit` | Delivers one Signal. |
| `Jido.Agent.Directive.reply/1` | `Jido.Agent.Directive.Reply` | Answers the current request. See [Agent Turns and Replies](turns-state-and-replies.md). |
| `Jido.Agent.Directive.agent_send/2` | `Jido.Agent.Directive.AgentSend` | Sends one Signal to a tracked child Agent. |
| `Jido.Agent.Directive.parent_send/1` | `Jido.Agent.Directive.ParentSend` | Sends one Signal to the parent Agent. |
| `Jido.Agent.Directive.server_stop/1` | `Jido.Agent.Directive.ServerStop` | Stops the AgentServer. The default reason is `:normal`. |

Agent Directives request runtime work after the state commit. Runtime child
Directives such as `Jido.AgentServer.Directive.AgentStart` are covered in
[Runtime Effects](../agent-servers/runtime-directives-and-effects.md).

### Emit a Signal

`emit/2` has two forms:

- `emit("type", %{data})` builds the Signal when the Turn finishes, using the Agent's `signal_source`. The type must be exact, and the data must be a plain static Map.
- `emit(signal)` or `emit(signal, dispatch)` keeps the Signal you built. The optional second argument is a Signal dispatch configuration.

The first form fails the Turn when the Agent has no `signal_source`.

An AgentServer delivers an `Emit` with no dispatch by looking for connections, then the parent, then its `:default_dispatch` option, then its own server. [Transforms and Forwards](route-transforms-and-forwards.md#where-the-output-goes) lists the rules. This Agent has none of the first three, so `order.closed` returns to it as a new Turn.

```elixir
{:ok, _instance} = Jido.start(name: DirectiveGuide.Jido)
{:ok, server} = Jido.start_agent(DirectiveGuide.Jido, DirectiveGuide.OrderBook, id: "book-live")
:ok = Jido.AgentServer.await_ready(server)

{:ok, %{state: %{sent: 0}}, [_emit]} =
  Jido.AgentServer.call(server, DirectiveGuide.OrderBook.close_signal!(%{order_id: "o-2"}))

# The follow-up Turn runs after the first Turn commits, so wait for it.
Enum.find(1..100, fn _attempt ->
  Process.sleep(10)
  Jido.AgentServer.snapshot(server).agent.state.sent == 1
end)

%{sent: 1, closed: ["o-2"]} = Jido.AgentServer.snapshot(server).agent.state
```

## How a batch runs

A Turn validates the whole batch before anything happens. One invalid Directive fails the Turn with no candidate, as this Reply without causation does:

```elixir
defmodule DirectiveGuide.BadReply do
  use Jido.Action, name: "directive_guide_bad_reply"

  @impl Jido.Action
  def run(_input, %{agent_state: state}) do
    uncorrelated = Jido.Signal.new!("order.answer", %{}, source: "/orders")
    {:ok, state, [Jido.Agent.Directive.reply(uncorrelated)]}
  end
end

strict =
  Jido.Agent.define!(%{
    name: "strict_book",
    routes: [%{path: "order.ask", handler: %{kind: :action, target: DirectiveGuide.BadReply}}]
  })
  |> Jido.Agent.instantiate!(id: "strict-1")

ask = Jido.Signal.new!("order.ask", %{}, source: "/orders/api")
{:error, %Jido.Error.ValidationError{}} = Jido.Agent.cmd(strict, ask)
```

An AgentServer then follows this order:

1. It validates the batch for the runtime. A `ServerStop` that is not last fails the Turn, and so does a batch larger than the `:max_directives_per_turn` option.
2. It commits the candidate.
3. It runs the Directives one at a time, in order.

Commit comes first, so a later dispatch failure does not undo the state. That failure does prevent the remaining Directives in the batch. A later state change must enter through a new Signal.

`Jido.Agent.cmd/3` does none of this. It returns the batch to you.

```elixir
archive = Jido.Signal.new!("order.archive", %{}, source: "/orders/api")

{:ok, _agent, [%Jido.Agent.Directive.Emit{}, %Jido.Agent.Directive.ServerStop{reason: :normal}]} =
  DirectiveGuide.OrderBook.cmd(book, archive)

monitor = Process.monitor(server)
{:ok, _stopped, _batch} = Jido.AgentServer.call(server, archive)

receive do
  {:DOWN, ^monitor, :process, ^server, :normal} -> :stopped
after
  1_000 -> raise "the server did not stop"
end
```

[Runtime Effects](../agent-servers/runtime-directives-and-effects.md) covers failure handling for each effect.

## Directives or direct I/O

An Action can do synchronous I/O before it returns. That work is outside the state transaction, so it stays done if the Turn later fails validation.

Choose a Directive when the work must happen only after commit, such as sending a notification about the new state. Do the I/O in the Action when the next state depends on its result.

## Custom Directives

A custom Directive is a struct that a Plugin owns. Without an owner, the Turn fails.

```elixir
defmodule DirectiveGuide.SendReceipt do
  use Jido.Agent.Directive

  defstruct [:order_id]
end
```

A Plugin claims the struct with its `directives/1` callback, and must also reduce state or dispatch runtime work. An Action returns the struct like any other Directive.

```elixir
defmodule DirectiveGuide.Receipts do
  use Jido.Plugin

  @impl true
  def directives(_opts), do: [DirectiveGuide.SendReceipt]

  @impl true
  def dispatch(_runtime, %DirectiveGuide.SendReceipt{}, _context, _opts), do: :ok
end

defmodule DirectiveGuide.RequestReceipt do
  use Jido.Action, name: "directive_guide_request_receipt"

  @impl Jido.Action
  def run(_input, %{agent_state: state}),
    do: {:ok, state, [%DirectiveGuide.SendReceipt{order_id: "o-3"}]}
end

route = %{path: "order.receipt", handler: %{kind: :action, target: DirectiveGuide.RequestReceipt}}
receipt = Jido.Signal.new!("order.receipt", %{}, source: "/orders/api")

without_owner = Jido.Agent.instantiate!(Jido.Agent.define!(%{name: "no_owner", routes: [route]}), id: "a-1")

{:error, %Jido.Error.ValidationError{message: "Agent Directive has no owner"}} =
  Jido.Agent.cmd(without_owner, receipt)

defmodule DirectiveGuide.ReceiptAgent do
  use Jido.Agent, name: "receipts", plugins: [DirectiveGuide.Receipts]

  routes do
    route "order.receipt", DirectiveGuide.RequestReceipt
  end
end

{:ok, _agent, [%DirectiveGuide.SendReceipt{order_id: "o-3"}]} =
  DirectiveGuide.ReceiptAgent.cmd(DirectiveGuide.ReceiptAgent.instantiate!(id: "a-2"), receipt)
```

`use Jido.Agent.Directive` adds a default `validate/1`, which applies `schema/0` when the module defines it. Override `validate/1` for another rule. The Plugin's `dispatch/4` callback does the work after commit. See [Custom Directives](../plugins/plugin-custom-directives.livemd).

## Related

- [Agent Turns and Replies](turns-state-and-replies.md) explains the steps of a Turn.
- [Outputs and Effects](../actions/action-effects.livemd) covers Action output.
