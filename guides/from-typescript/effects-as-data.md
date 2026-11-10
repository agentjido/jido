# Effects as Data

This guide explains why a Jido handler returns its side effects as a list of values, what that gives you, and where the guarantee stops. If you have kept a Redux reducer pure and moved I/O elsewhere, you know the idea.

## Inline effects and returned effects

A common TypeScript handler performs its effects as it goes.

```typescript
async function placeOrder(db: Db, mailer: Mailer, order: Order): Promise<void> {
  await db.orders.insert(order);
  await mailer.sendReceipt(order.id);
}
```

This code is direct, and it has three properties that matter in a long-running service. A test needs a fake `db` and `mailer`. The decision and the I/O sit together, so the only record of what was intended is what happened. A check that fails after the send cannot take the email back.

The other style returns a description of the work, and a small piece of code performs it after the state is saved.

```typescript
type Effect = { type: "sendReceipt"; orderId: string };

function placeOrder(state: State, order: Order): { state: State; effects: Effect[] } {
  return {
    state: { ...state, placed: state.placed + 1 },
    effects: [{ type: "sendReceipt", orderId: order.id }],
  };
}

const { state: next, effects } = placeOrder(state, order);
await save(next);
for (const effect of effects) await perform(effect);
```

Jido builds in the second style. A value that describes an effect is a Directive, and the loop at the bottom belongs to `Jido.AgentServer`.

## Return a Directive

An Action on an Agent route returns the next state and a list of Directives. Here a Directive type, `SendReceipt`, takes the place of the `Effect` type, and a Plugin's `dispatch/4` takes the place of `perform`. Elixir's built-in `Agent` stands in for a mail service.

```elixir
{:ok, _mailbox} = Agent.start(fn -> [] end, name: EffectsGuide.Mailbox)

defmodule EffectsGuide.SendReceipt do
  use Jido.Agent.Directive

  defstruct [:order_id]
end

defmodule EffectsGuide.Receipts do
  use Jido.Plugin

  @impl true
  def directives(_opts), do: [EffectsGuide.SendReceipt]

  @impl true
  def dispatch(_runtime, %EffectsGuide.SendReceipt{order_id: order_id}, _context, _opts) do
    Agent.update(EffectsGuide.Mailbox, &[order_id | &1])
  end
end

defmodule EffectsGuide.PlaceOrder do
  use Jido.Action,
    name: "effects_guide_place_order",
    schema: Jido.Joi.object(%{order_id: Jido.Joi.string()})

  @impl true
  def run(%{order_id: order_id}, %{agent_state: state}) do
    {:ok, %{state | placed: state.placed + 1}, [%EffectsGuide.SendReceipt{order_id: order_id}]}
  end
end

defmodule EffectsGuide.Orders do
  use Jido.Agent, name: "effects_guide_orders", plugins: [EffectsGuide.Receipts]

  state do
    schema Jido.Joi.object(%{placed: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/orders"

    route "order.place", EffectsGuide.PlaceOrder, as: :place

    # This handler requests a receipt, then returns a state its schema rejects.
    route "order.place_invalid", as: :place_invalid do
      action %{order_id: order_id},
        schema: Jido.Joi.object(%{order_id: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | placed: "many"}, [%EffectsGuide.SendReceipt{order_id: order_id}]}
      end
    end

    route "order.place_with_tuple", as: :place_with_tuple do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state, [{:send_receipt, "o-9"}]}
      end
    end
  end
end
```

## Test the decision with no fakes

`Jido.Agent.cmd/3` runs a Turn on a value and hands you the Directives. It performs none of them. A test asserts on the returned data, with no mock and no process.

```typescript
const mailer = { sendReceipt: vi.fn() };
await placeOrder(fakeDb, mailer, { id: "o-1" });
expect(mailer.sendReceipt).toHaveBeenCalledWith("o-1");
```

```elixir
orders = EffectsGuide.Orders.instantiate!(id: "orders-1")
place = EffectsGuide.Orders.place_signal!(%{order_id: "o-1"})

{:ok, %{state: %{placed: 1}}, [%EffectsGuide.SendReceipt{order_id: "o-1"}]} =
  EffectsGuide.Orders.cmd(orders, place)

[] = Agent.get(EffectsGuide.Mailbox, & &1)
```

The mailbox is empty, because `cmd/3` only described the receipt.

## The server performs effects after commit

An AgentServer runs the same Turn, commits the next state, replies to the caller, and then runs the Directives in order. Each effect runs in its own task, and queued Turns wait for the batch to finish. `Jido.AgentServer.call/3` returns before the effects finish, so this example waits for the mailbox.

```elixir
{:ok, _instance} = Jido.start(name: EffectsGuide.Jido)
{:ok, server} = Jido.start_agent(EffectsGuide.Jido, EffectsGuide.Orders, id: "orders-live")
:ok = Jido.AgentServer.await_ready(server)

{:ok, %{state: %{placed: 1}}, [%EffectsGuide.SendReceipt{}]} = Jido.AgentServer.call(server, place)

Enum.find(1..100, fn _attempt ->
  Process.sleep(10)
  Agent.get(EffectsGuide.Mailbox, & &1) != []
end)

["o-1"] = Agent.get(EffectsGuide.Mailbox, & &1)
```

## A failed Turn performs nothing

The `order.place_invalid` route returns a valid Directive with an invalid state. The Turn fails, nothing commits, and the receipt never runs. An inline `await mailer.sendReceipt()` would already have sent it.

```elixir
invalid = EffectsGuide.Orders.place_invalid_signal!(%{order_id: "o-2"})

{:error, %Jido.Error.ValidationError{code: :invalid_state}} = Jido.AgentServer.call(server, invalid)

next_order = EffectsGuide.Orders.place_signal!(%{order_id: "o-3"})
{:ok, %{state: %{placed: 2}}, _batch} = Jido.AgentServer.call(server, next_order)

Enum.find(1..100, fn _attempt ->
  Process.sleep(10)
  length(Agent.get(EffectsGuide.Mailbox, & &1)) == 2
end)

["o-3", "o-1"] = Agent.get(EffectsGuide.Mailbox, & &1)
```

The mailbox has a receipt for each valid order, and none for `o-2`.

## Jido checks the batch first

A closure is opaque until it runs. A Directive is a struct, so Jido can validate the whole batch before anything happens. A Directive with an unknown shape or no owner fails the Turn, and no effect in that batch runs.

```elixir
{:error, %Jido.Error.ValidationError{message: "Agent executable returned an invalid Directive"}} =
  Jido.Agent.cmd(orders, EffectsGuide.Orders.place_with_tuple_signal!(%{}))

:ok = Jido.stop(EffectsGuide.Jido)
```

The built-in Directives cover common work, such as `Jido.Agent.Directive.emit/2` to deliver a Signal and `Jido.Agent.Directive.reply/1` to answer the current request. See [State and Directives](../agents/agent-results-and-directives.md).

## Where the guarantee stops

A Directive runs after commit, and Jido does not save its progress. Do not read it as a transactional outbox or a job queue.

| Situation | What happens |
| --- | --- |
| An effect returns an error or raises | The commit stands, the rest of the batch does not run, and the server records the outcome in `last_effect_outcome` |
| The caller wants to know the effect ran | `call/3` has already returned. Read `Jido.AgentServer.status/2` |
| The server crashes during the effects | The interrupted batch is not run again after the restart |
| An effect should be retried | Jido does not retry effects |

For a notification you can afford to lose, a Directive fits. For work that must eventually happen, record it in Agent state in the same Turn and let a later Signal retry it, or use a Flow step before commit and accept that the step can repeat. [Runtime Effects](../agent-servers/runtime-directives-and-effects.md) and [Recovery Limits](../durability/recovery-and-effect-limits.md) give the details.

## Choose between a Directive and I/O in the Action

An Action is ordinary code, and it can call a database or an API. Returning effects as data does not forbid that.

| Do the work | When | TypeScript shape |
| --- | --- | --- |
| In the Action | The next state depends on the result, such as a price from a pricing API | `const price = await getPrice(sku)`, then use it |
| In a Directive | The work follows from the new state, such as a notification about it | Push onto `effects` and return |

I/O in an Action happens before commit, so it stays done even when the Turn fails later. A retry also repeats it, because a retry runs `run/2` again. Effects behave differently: a failed attempt's list is discarded, so only the attempt that succeeds returns effects.

```elixir
defmodule EffectsGuide.FlakyRefund do
  use Jido.Action, name: "effects_guide_flaky_refund"

  @impl true
  def run(%{order_id: order_id}, %{attempts: attempts}) do
    :counters.add(attempts, 1, 1)

    if :counters.get(attempts, 1) == 1 do
      {:error, Jido.Error.execution_error("ledger busy"), [{:send_refund_email, order_id}]}
    else
      {:ok, %{order_id: order_id}, [{:send_refund_email, order_id}]}
    end
  end
end

attempts = :counters.new(1, [])

{:ok, %{order_id: "o-4"}, [{:send_refund_email, "o-4"}]} =
  Jido.Exec.run(EffectsGuide.FlakyRefund, %{order_id: "o-4"}, %{attempts: attempts}, max_attempts: 2)

2 = :counters.get(attempts, 1)
```

## Effects outside an Agent

The example above ran with no Agent. `Jido.Exec.run/4` returns the list and does not read or perform it, so its elements can be any term that you and the Action agree on. You are the interpreter, as with the TypeScript loop earlier. A Flow collects the effects of its components in the same way.

```elixir
defmodule EffectsGuide.ApproveRefund do
  use Jido.Action, name: "effects_guide_approve_refund"

  @impl true
  def run(%{order_id: order_id}, _context) do
    {:ok, %{order_id: order_id}, [{:send_refund_email, order_id}]}
  end
end

defmodule EffectsGuide.RefundFlow do
  use Jido.Flow, name: "effects_guide_refund_flow"

  flow do
    step "refund", action: EffectsGuide.ApproveRefund, params: %{order_id: input(:order_id)}
    output result("refund")
  end
end

{:ok, %{order_id: "o-5"}, [{:send_refund_email, "o-5"}] = effects} =
  Jido.Exec.run(EffectsGuide.RefundFlow, %{order_id: "o-5"})

[sent: "o-5"] = for {:send_refund_email, order_id} <- effects, do: {:sent, order_id}
```

An Agent is stricter. Its handlers must return real Directives, as the tuple route above showed. See [Outputs and Effects](../actions/action-effects.livemd).

## Next steps

- [State and Directives](../agents/agent-results-and-directives.md) lists what a handler can return.
- [Custom Directives](../plugins/plugin-custom-directives.livemd) builds Directive types that a Plugin owns.
- [Runtime Effects](../agent-servers/runtime-directives-and-effects.md) covers limits and failure handling.
