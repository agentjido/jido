# Jido Mental Model

Jido keeps Agent behavior in validated data and functions, then runs that behavior in OTP processes when you need it live. This guide names each piece and shows how one Signal moves through them.

## The pieces

| Piece | What it is | Module | Runs as a process? |
| --- | --- | --- | --- |
| Action | One named unit of work with a validated input and output. | `Jido.Action` | Only while it runs |
| Flow | A named graph of Action calls, declared as data. | `Jido.Flow` | Only while it runs |
| Signal | An event envelope with a `type`, a `source`, and `data`. | `Jido.Signal` | No |
| Agent definition | Declares a state schema, routes, and Plugins. It has no identity. | `Jido.Agent` | No |
| Agent instance | A definition with an `id` and complete `state`. It is an immutable value. | `Jido.Agent` | No |
| Turn | One evaluation of one Signal against one Agent instance. | `Jido.Agent.cmd/3` | No, unless a server runs it |
| Directive | A request for an effect, returned as data. | `Jido.Agent.Directive` | No |
| AgentServer | The process that holds one committed Agent and runs its Turns one at a time. | `Jido.AgentServer` | Yes |
| Jido instance | A named supervisor that owns AgentServers and their registry. | `Jido` | Yes |
| Plugin | A reusable module that adds state fields and runs Agent and server callbacks. | `Jido.Plugin` | Only if it starts a resource |

Each row builds on the ones you already have. You can stop at the row that solves your problem. An Action needs no Agent, and an Agent needs no process.

## The path of one Signal

A live Turn takes this path:

```text
Signal
  -> AgentServer queue
  -> first matching route on the Agent
  -> Action or Flow, with the Agent state in its context
  -> next state and Directives
  -> validate the next state against the schema
  -> commit
  -> perform the Directives
```

The rest of this guide runs that path in code. The Agent keeps a payment total for one invoice.

```elixir
defmodule MentalModel.ApplyPayment do
  use Jido.Action,
    name: "mental_model_apply_payment",
    schema: Jido.Joi.object(%{amount_cents: Jido.Joi.integer() |> Jido.Joi.min(1)})

  @impl true
  def run(%{amount_cents: amount}, %{agent_state: state}) do
    {:ok, %{state | paid_cents: state.paid_cents + amount}}
  end
end

defmodule MentalModel.InvoiceAgent do
  use Jido.Agent, name: "mental_model_invoice"

  state do
    schema Jido.Joi.object(%{paid_cents: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/billing/invoice"

    route "invoice.payment.apply", MentalModel.ApplyPayment, as: :apply_payment do
      reply "invoice.payment.applied", from: output()
    end
  end
end
```

The Action holds the behavior. The Agent module holds the state contract and the route from a Signal type to that Action. Neither one starts a process.

## A Turn is a function

`cmd/3` takes an Agent value and a Signal. It returns a new Agent value and a list of Directives.

```elixir
invoice = MentalModel.InvoiceAgent.instantiate!(id: "inv-1001")
signal = MentalModel.InvoiceAgent.apply_payment_signal!(%{amount_cents: 1_500})

{:ok, paid, [%Jido.Agent.Directive.Reply{}]} = MentalModel.InvoiceAgent.cmd(invoice, signal)

{0, 1_500} = {invoice.state.paid_cents, paid.state.paid_cents}
```

The source value keeps its old state. The Reply Directive has not been sent, because nothing here performs Directives. This form needs no setup, so most Agent tests use it.

## An AgentServer makes the Turn live

An AgentServer runs the same evaluation and adds what a long-lived Agent needs: a queue, a committed state, a state version, and Directive delivery.

```elixir
{:ok, _instance} = Jido.start(name: MentalModel.Jido)
{:ok, server} = Jido.start_agent(MentalModel.Jido, MentalModel.InvoiceAgent, id: "inv-1001")
:ok = Jido.AgentServer.await_ready(server)

{:ok, committed, [%Jido.Agent.Directive.Reply{}]} = Jido.AgentServer.call(server, signal)
true = committed.state == paid.state

%Jido.Signal{type: "invoice.payment.applied"} =
  receive do
    %Jido.Signal{} = reply -> reply
  after
    1_000 -> :no_reply
  end

:ok = Jido.stop(MentalModel.Jido)
```

The committed state equals the pure result. This time the server also performed the Directive, so the reply arrived as a message.

## Three ideas that hold everywhere

**A failed Turn changes no Agent data.** A Turn produces a complete next state or an error. On an error, the source value or the committed state stays as it was.

**An Action can do I/O, and a Directive waits for commit.** An Action runs ordinary code, so a database write it makes stays done even if the Turn later fails. When an effect must happen only after a commit, return a Directive and let the server perform it.

**Definitions are data.** Agents and Flows compile to validated values. Jido can inspect, compare, and store them, and you can build the same values from Maps at runtime.

## Choose where to start

- You have one function that needs validation, a timeout, or retries: write an [Action](first-action.livemd).
- You have several Actions connected by data: write a [Flow](build-your-first-flow.livemd).
- You need state that changes across Signals: write an [Agent](first-agent.livemd).
- You need that Agent running, addressable, and supervised: start it in a [Jido instance](start-a-jido-instance.livemd).

An AI Agent uses the same pieces. `Jido.AI` defines a normal Agent whose request route targets a reasoning Flow. See [Graph-First AI Agents](../ai/graph-first-ai-agents.livemd).

## Next steps

- [Getting Started](getting-started.livemd) installs Jido and runs this path in a new project.
- [Life of a Signal](../core-concepts/signal-to-effects.md) follows a Signal through each runtime stage.
- [Pure or Live Execution](../core-concepts/pure-or-live-execution.md) compares the two ways to run a Turn.
