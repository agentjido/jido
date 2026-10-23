# Recovery Limits

Jido recovers committed Agent state. It doesn't recover work outside that
state: Action I/O, `after_commit/3` hooks, Directives, and Signals that never
committed. This guide lists what each failure recovers to, shows the one case
where storage is ahead of what the caller saw, and gives three patterns that
make external effects safe to repeat.

```elixir
# The store saves revision 2, then the write call times out.
Jido.AgentServer.call(counter, signal)
# => {:error, %Jido.Error.ExecutionError{
#      message: "Required durable commit failed",
#      details: %{reason: {:indeterminate, :timeout}}}}

# The activation stopped. Its Emit Directive never ran.
{:ok, counter} =
  MyApp.Jido.start_agent(MyApp.Counter,
    id: "counter-1",
    persistence: :inherit,
    persistence_mode: :restore
  )

:ok = Jido.AgentServer.await_ready(counter)
{Jido.AgentServer.agent(counter).state, Jido.AgentServer.status(counter).state_version}
# => {%{count: 2}, 2}
# The restored Agent has the Turn. Nothing re-emits it.
```

The caller got an error, but the Turn is committed. The Directive from that
Turn is lost for good. The patterns at the end of this guide close that gap.

## What Recovers

| Failure | Without persistence | With persistence |
| --- | --- | --- |
| Agent Server process crash | Last committed Agent and revision | Last committed Agent and revision |
| Activation root crash | Initial state at revision 0 | Last stored revision |
| BEAM restart | Nothing | Last stored revision, after you start the Agent with `persistence_mode: :restore` |
| Failed commit write | — | Activation stops; storage keeps whatever the store holds |

Measured with a counter at `count: 4`, revision 2:

| Kill | Without persistence | With persistence |
| --- | --- | --- |
| Server process | `{%{count: 4}, 2}` | `{%{count: 4}, 2}` |
| Activation root | `{%{count: 0}, 0}` | `{%{count: 4}, 2}` |

### Server Crash

Each activation keeps an in-memory checkpoint of the last committed Agent and
revision. When the Server process dies, its supervisor starts a new one from
that checkpoint. The checkpoint is local memory, not storage. The in-flight
Turn is lost and isn't replayed. Its caller gets an exit.

### Activation Loss

When the whole activation dies, the memory checkpoint goes with it. Without
persistence, the restart begins again from the initial state at revision 0,
with no error. With persistence, the restart reloads the stored record. It
switches to restore mode on its own, so a `:create` start doesn't conflict
with its own record.

### BEAM Restart

Only an adapter that writes outside the BEAM survives. The ETS adapter
doesn't. With `Jido.Persistence.File`, a second run restores what the first
run saved:

```text
run 1, persistence_mode: :create   => {%{count: 5}, 1}
run 2, persistence_mode: :restore  => {%{count: 10}, 2}
run 3, persistence_mode: :create   => await_ready exits {:shutdown, :conflict}
```

Jido doesn't start Agents on boot. Start each one you need with
`persistence_mode: :restore`, or call `thaw`. See
[Durable Activation](durable-agent-activation.livemd).

### Storage Failure

A failed commit write stops the activation with `:shutdown` and doesn't
restart it. What storage holds depends on the result:

| Store result | Stored | Caller sees |
| --- | --- | --- |
| `:conflict` | The other writer's record | `%{reason: :conflict}` |
| `{:rejected, reason}` | The previous revision | `%{reason: {:rejected, reason}}` |
| `{:indeterminate, reason}` | Previous or new revision | `%{reason: {:indeterminate, reason}}` |

In every case, no hooks or Directives run. After an indeterminate result,
restore and inspect the revision before you retry.
[Revisions and Conflicts](durable-revisions-and-conflicts.md) covers the
conflict rules.

## Not Replayed

Restore loads state. It never runs anything again:

- **`after_commit/3` hooks and Directives.** They run once after the commit,
  in the activation that committed. If the activation dies first, or a hook
  fails, they don't run later.
- **Signals.** A Signal is input to one Turn. Jido has no durable inbox.
  Signals queued in the Server's mailbox are lost with the process. A Signal
  sent again is a new Turn.
- **Callers.** A restored Agent doesn't reply to a caller from the earlier
  activation. That caller already got an error or an exit.

## Action I/O Isn't Undone

An Action that calls an API, sends mail, or writes another database does it
before the commit. If the Turn later fails in validation, in the save, or in
a conflict, the committed state stays the same and the external work stays
done. Jido doesn't run compensation.

## Durable Flow Steps

With persistence on, a Flow Turn saves its acceptance before it runs, saves a
graph checkpoint after each step before the next step starts, and saves the
final state with its completion. After a crash, recovery reloads the same
Turn and continues from the last saved checkpoint. A step that was running
when the crash happened has no checkpoint, so it runs again. Make each step
safe to repeat. [Durable Turns and Flows](durable-turns-and-flows.livemd)
covers waits, timers, and compatibility.

## No Exactly-Once

Jido gives you exactly one committed revision per successful Turn. It
doesn't give exactly-once delivery of anything outside the Agent. Every
external effect runs zero times, once, or more than once, depending on where
the failure falls. Design for at-least-once delivery with deduplication.

## Patterns

The three patterns below share one Agent. It records orders, keeps an
outbox of receipts to send, and emits each receipt with a stable ID:

```elixir
defmodule MyApp.PlaceOrder do
  use Jido.Action,
    name: "place_order",
    schema: Zoi.object(%{order_id: Zoi.string(), total: Zoi.integer()}),
    output_schema: Zoi.map()

  alias Jido.Agent.Directive

  @impl true
  def run(%{order_id: id}, %{agent_state: state}) when is_map_key(state.orders, id),
    do: {:ok, state, []}

  def run(%{order_id: id, total: total}, %{agent_state: state}) do
    effect_id = "receipt:" <> id
    receipt = %{effect_id: effect_id, order_id: id, total: total}

    {:ok,
     %{
       state
       | orders: Map.put(state.orders, id, total),
         outbox: Map.put(state.outbox, effect_id, receipt)
     }, [Directive.emit("receipt.requested", receipt)]}
  end
end

defmodule MyApp.ReceiptSent do
  use Jido.Action, name: "receipt_sent", schema: Zoi.object(%{effect_id: Zoi.string()}), output_schema: Zoi.map()

  @impl true
  def run(%{effect_id: effect_id}, %{agent_state: state}),
    do: {:ok, %{state | outbox: Map.delete(state.outbox, effect_id)}, []}
end

defmodule MyApp.Redeliver do
  use Jido.Action, name: "redeliver", output_schema: Zoi.map()

  @impl true
  def run(_params, %{agent_state: state}) do
    directives =
      for {_id, receipt} <- state.outbox,
          do: Jido.Agent.Directive.emit("receipt.requested", receipt)

    {:ok, state, directives}
  end
end

defmodule MyApp.Orders do
  use Jido.Agent, name: "orders"

  state do
    schema(
      Zoi.object(%{
        orders: Zoi.map() |> Zoi.default(%{}),
        outbox: Zoi.map() |> Zoi.default(%{})
      })
    )
  end

  routes do
    signal_source("/my_app/orders")
    route "order.place", MyApp.PlaceOrder, as: :place do
      state from: output()
    end
    route "receipt.sent", MyApp.ReceiptSent, as: :receipt_sent do
      state from: output()
    end
    route "outbox.redeliver", MyApp.Redeliver, as: :redeliver do
      state from: output()
    end
  end
end
```

### Idempotency Keys

Key each Turn on a business ID and keep the IDs you've applied in state. A
repeated Signal finds its key and returns the state unchanged with no
Directives:

```elixir
place = MyApp.Orders.place_signal!(%{order_id: "o-1", total: 40})

{:ok, _agent, [_emit]} = Jido.AgentServer.call(orders, place)
{:ok, _agent, []} = Jido.AgentServer.call(orders, place)
```

The second call still commits a new revision. Use a business ID, not the
Signal `id`, when a sender can build a new Signal for the same request.

### Outbox Directives

Save the intent to act in the same Turn as the state change, then act in a
Directive. The intent commits with the state, so it survives anything the
Directive doesn't. In the lost-reply case above, storage has `o-2`, and the
emit never ran:

```elixir
Jido.AgentServer.agent(orders).state.outbox
# => %{"receipt:o-2" => %{effect_id: "receipt:o-2", order_id: "o-2", total: 15}}

redeliver = MyApp.Orders.redeliver_signal!()
{:ok, _agent, [_emit]} = Jido.AgentServer.call(orders, redeliver)
```

Send `receipt.sent` when the receiver confirms, to clear the entry. Send
`outbox.redeliver` after each restore, or on a schedule with
[Heartbeats and Schedules](heartbeats-and-schedules.livemd).

### Effect IDs

Give each effect an ID derived from state, such as `"receipt:o-2"`, never a
random value or a timestamp. A redelivery then carries the same ID as the
first try. The receiver stores the IDs it has applied and treats a repeated
ID with the same value as success. With this, at-least-once delivery has
exactly-once results at the receiver.

Example `10_07_recoverable_delivery` builds the same pattern with
Plugin-owned state and a supervised worker. Completed IDs need a retention
policy so the set doesn't grow forever.

## Next

- [Durability Model](durability-model.md) – the full list of guarantees and
  non-guarantees.
- [Revisions and Conflicts](durable-revisions-and-conflicts.md) – conflict
  and indeterminate writes in detail.
- [Checkpoints and Upgrades](checkpoints-and-data-upgrades.md) – what a
  stored revision contains.
