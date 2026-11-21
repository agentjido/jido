# Agent Turns and Replies

A Turn is one complete evaluation of one Signal against one Agent value. This guide explains what happens in a Turn, what a caller gets back, and how a reply reaches that caller.

The examples use this quote Agent.

```elixir
defmodule TurnGuide.PriceQuote do
  use Jido.Action,
    name: "turn_guide_price_quote",
    schema: Jido.Joi.object(%{quantity: Jido.Joi.integer() |> Jido.Joi.min(1)}),
    output_schema:
      Jido.Joi.object(%{
        next_state: Jido.Joi.map(),
        quote: Jido.Joi.object(%{total_cents: Jido.Joi.integer()})
      })

  @impl Jido.Action
  def run(%{quantity: quantity}, %{agent_state: state}) do
    {:ok,
     %{
       next_state: %{state | quoted: state.quoted + 1},
       quote: %{total_cents: quantity * state.unit_cents}
     }}
  end
end

defmodule TurnGuide.QuoteAgent do
  use Jido.Agent, name: "quote_desk"

  state do
    schema Jido.Joi.object(%{
             unit_cents: Jido.Joi.integer() |> Jido.Joi.default(250),
             quoted: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/sales/quote"

    route "quote.request", TurnGuide.PriceQuote, as: :request do
      state from: output(:next_state)
      reply "quote.ready", from: output(:quote)
    end

    route "quote.acknowledge", as: :acknowledge do
      action %{ticket: ticket}, schema: Jido.Joi.object(%{ticket: Jido.Joi.string()}), context: context do
        {:ok, reply} = Jido.Agent.build_signal(context, "quote.acknowledged", %{ticket: ticket})
        {:ok, context.agent_state, [Jido.Agent.Directive.reply(reply)]}
      end
    end

    route "quote.bad_price" do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | unit_cents: "free"}}
      end
    end
  end
end
```

## Two ways to run a Turn

`Jido.Agent.cmd/3` runs a Turn on a value. It needs no process. It does not dispatch Directives, save state, resume work, or deduplicate input.

```elixir
desk = TurnGuide.QuoteAgent.instantiate!(id: "desk-1")
request = TurnGuide.QuoteAgent.request_signal!(%{quantity: 4})

{:ok, candidate, [%Jido.Agent.Directive.Reply{signal: %{data: %{total_cents: 1000}}}]} =
  Jido.Agent.cmd(desk, request)

{0, 1} = {desk.state.quoted, candidate.state.quoted}
```

`Jido.AgentServer.call/3` submits the same Signal to a live Agent. The server runs the same evaluation, commits the result, and then performs the Directives.

```elixir
{:ok, _instance} = Jido.start(name: TurnGuide.Jido)
{:ok, server} = Jido.start_agent(TurnGuide.Jido, TurnGuide.QuoteAgent, id: "desk-live")
:ok = Jido.AgentServer.await_ready(server)

{:ok, committed, [%Jido.Agent.Directive.Reply{}]} = Jido.AgentServer.call(server, request)

true = committed.state == candidate.state
%{state_version: 1} = Jido.AgentServer.snapshot(server)
```

[Pure or Live Execution](../core-concepts/pure-or-live-execution.md) compares the two paths. The live path adds Plugin admission and outbound Signal preparation.

## What happens in a Turn

A Turn runs these steps in order. The first failure stops it.

1. **Check the input.** Jido validates the instance, the Signal, and the caller context.
2. **Prepare Plugins.** Each Plugin can compute input for this Turn.
3. **Select one route.** The first matching route wins, and its defaults merge with the Signal data. See [Routes and Handlers](build-agent-routes.livemd).
4. **Run the handler.** `cmd/3` runs the Action or Flow through `Jido.Exec.run/4`. A live AgentServer compiles it with `Jido.Exec.compile/2` and runs it in a Runic Worker.
5. **Project the output.** The route's `state` and `reply` selectors produce the next state and any reply Directive.
6. **Reduce Plugins.** Jido rejects a change to Plugin-owned state, validates every Directive, and lets each Plugin update its own field.
7. **Validate the candidate.** Jido checks the complete next state against the schema and preserves the definition.

The result is one of:

| Result | Meaning |
| --- | --- |
| `{:ok, agent, directives}` | A complete next value and an ordered Directive batch. |
| `{:handoff, agent, instruction, directives}` | A Flow ended in a Handoff. The successor is validated but not run. See [Execute Flows](../flow-runtime/flow-execution.livemd). |
| `{:error, reason}` | The Turn failed. No candidate exists. |

## A failed Turn changes nothing

A failure at any step leaves the source value alone. A live Agent keeps its committed state and revision, and the server stays available.

```elixir
bad = Jido.Signal.new!("quote.bad_price", %{}, source: "/sales/api")

{:error, %Jido.Error.ValidationError{code: :invalid_state}} = Jido.Agent.cmd(desk, bad)
{:error, %Jido.Error.ValidationError{code: :invalid_state}} = Jido.AgentServer.call(server, bad)

%{state_version: 1} = Jido.AgentServer.snapshot(server)
```

This protection covers Agent data. An Action runs ordinary application code, so an HTTP call or a database write it made before the failure stays done. Use a Directive for work that must wait for commit. See [State and Directives](agent-results-and-directives.md).

## What the handler sees

Jido merges these keys into the execution context:

| Key | Value |
| --- | --- |
| `:agent_id` | The instance ID |
| `:agent_module` | The Agent module, or `nil` |
| `:agent_signal_source` | The definition's `signal_source` |
| `:agent_state` | The state at the start of the Turn |
| `:agent_topology` | The definition's topology data |
| `:plugin_inputs` | Plugin preparation results for this Turn |
| `:signal` | The source Signal |

Callers can add other keys with the `:context` option. A reserved key returns an error. All other options to `Jido.Agent.cmd/3` pass to `Jido.Exec.run/4`. See [Action Context](../actions/action-context.md) and [Execution Policy](../actions/action-execution-policy.md).

```elixir
{:ok, _agent, _directives} = Jido.Agent.cmd(desk, request, context: %{tenant: "acme"}, timeout: 5_000)

{:error, %Jido.Error.ValidationError{details: %{keys: [:agent_id]}}} =
  Jido.Agent.cmd(desk, request, context: %{agent_id: "other"})
```

## Replies

A reply is one Signal that answers the Signal that started the Turn. A `reply` declaration on a route is the normal way to create one. Jido builds the Signal from the selected output, sets its source to `signal_source`, and adds trace and causation data from the request.

The caller of `Jido.AgentServer.call/3` gets the Agent and the Directives as the return value. The reply Signal arrives as a message.

```elixir
reply =
  receive do
    %Jido.Signal{type: "quote.ready"} = signal -> signal
  after
    1_000 -> :no_reply
  end

%{total_cents: 1000} = reply.data
"/sales/quote" = reply.source
```

The batch can hold at most one `Jido.Agent.Directive.Reply`, and its causation must point at the current request. To build one in an Action, use `Jido.Agent.build_signal/3`, which sets the correlation from the Action context:

```elixir
ack = TurnGuide.QuoteAgent.acknowledge_signal!(%{ticket: "T-9"})
{:ok, _agent, [%Jido.Agent.Directive.Reply{signal: signal}]} = Jido.Agent.cmd(desk, ack)

true = Jido.Signal.get_context(signal, "jidocausationid") == ack.id
```

A generated reply is placed last in the batch, or immediately before a trailing `Jido.Agent.Directive.ServerStop`.

A reply needs a caller who can receive it. `Jido.AgentServer.cast/3` has none, so a cast that produces a reply fails before commit. `cast/3` itself still returns `:ok`, because it only confirms submission. A durable Turn can outlive its caller, and Jido drops the reply if that caller is gone.

```elixir
:ok = Jido.AgentServer.cast(server, request)

# A later call runs after the cast. The cast changed nothing.
{:error, _} = Jido.AgentServer.call(server, bad)
%{state_version: 1} = Jido.AgentServer.snapshot(server)
```

## Managed and durable Turns

The internal Runner lowers every selected Action or Flow to one Flow
instruction. `Jido.Agent.cmd/3` runs it in the calling process. An AgentServer
with persistence uses the durable Flow lifecycle. An AgentServer without
persistence runs the same instruction without durable checkpoints. See
[Durable Turns and Flows](../durability/durable-turns-and-flows.livemd).

## Related

- [Turns and Effects](../core-concepts/turns-commits-and-effects.md) explains the commit boundary.
- [Call, Cast, and Await](../agent-servers/send-signals-to-live-agents.livemd) covers the live request functions.
- [State and Directives](agent-results-and-directives.md) covers what a handler can return.
