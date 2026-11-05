# Signal Bus

Publish Signals to a local Bus, subscribe processes by type, filter by source and subject, and replay retained records. `Jido.Signal.Bus` is a GenServer on one node. It stores each record before it sends any message, and delivers in publication order.

This guide covers ordinary subscriptions, which last only while the target process is alive. Use [Durable Subscriptions](durable-subscriptions.md) when a consumer must not lose its place.

## Start a Bus

Add the Bus to your supervision tree. `:name` is required.

<!-- partial -->
```elixir
children = [
  {Jido.Signal.Bus, name: :ticket_events}
]
```

`Jido.Signal.Bus.start_link/1` starts one directly, and is what the examples below use.

| Option | Default | Value |
| --- | --- | --- |
| `:name` | Required | An atom or a non-empty string. |
| `:jido` | None | A namespace that isolates this name. See [Isolate Buses](#isolate-buses). |
| `:registry` | The package Registry | The Registry module that holds the name. |
| `:store` | `Jido.Signal.Bus.Store.Memory` | A `Jido.Signal.Bus.Store` module. |
| `:store_opts` | `[]` | Options for the store. |
| `:max_log_size` | `100_000` | The record limit for the memory store. |

An unknown option returns `{:error, {:invalid_options, message}}`.

## Publish and subscribe

`Jido.Signal.Bus.subscribe/3` selects Signals with a path. The path rules are the same as in [Signal Routing](routing-and-router-dsl.md), and a `use Jido.Signal` module also works. The calling process is the default target. It receives `{:signal, signal}`.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus
alias Jido.Signal.Bus.RecordedSignal

{:ok, bus} = Bus.start_link(name: :ticket_events)
{:ok, subscription_id} = Bus.subscribe(bus, "ticket.*")
true = is_binary(subscription_id)

opened = Signal.new!("ticket.opened", %{"ticket_id" => "t-81"}, source: "/support")
invoice = Signal.new!("invoice.paid", %{"invoice_id" => "inv-9"}, source: "/billing")

{:ok, [%RecordedSignal{cursor: 1}, %RecordedSignal{cursor: 2}]} = Bus.publish(bus, [opened, invoice])

^opened =
  receive do
    {:signal, signal} -> signal
  after
    1_000 -> :timeout
  end

:no_more_messages =
  receive do
    {:signal, _signal} -> :unexpected
  after
    100 -> :no_more_messages
  end
```

`Jido.Signal.Bus.publish/2` takes a list. It returns one `Jido.Signal.Bus.RecordedSignal` per Signal, with these fields:

- `cursor` is the record's position in this Bus. It starts at 1 and increases by one.
- `id` is a UUID7 for the record. It differs from the Signal's `id`.
- `type` is the Signal type.
- `created_at` is the `DateTime` of publication.
- `signal` is the published Signal.

A Signal that no subscription selects is still stored. A publish with an invalid item stores nothing and sends nothing.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.whereis(:ticket_events)
valid = Signal.new!("ticket.closed", %{}, source: "/support")

{:error, %Jido.Error.ValidationError{details: %{index: 1}}} = Bus.publish(bus, [valid, :not_a_signal])
{:error, :invalid_signals} = Bus.publish(bus, :not_a_list)
{:ok, []} = Bus.publish(bus, [])
```

## Address a Bus

The first argument of Bus functions can be a PID, the name, or `{name, registry}`. `Jido.Signal.Bus.whereis/2` returns the PID.

```elixir
alias Jido.Signal.Bus

{:ok, bus} = Bus.whereis(:ticket_events)
{:ok, ^bus} = Bus.whereis("ticket_events")
{:error, :not_found} = Bus.whereis(:missing_events)

{:ok, []} = Bus.publish(:ticket_events, [])
{:error, :not_found} = Bus.publish(:missing_events, [:any])
```

An atom and a string with the same text are the same name. A call to a Bus that is not running returns `{:error, :not_found}`.

## Choose a target and an ID

A subscription takes these options:

| Option | Value |
| --- | --- |
| `:target` | A live local PID. Defaults to the caller. |
| `:subscription_id` | A non-empty string. Defaults to a generated UUID7. |
| `:selector` | Exact `source` and `subject` matching. |
| `:durable` | A stable ID. See [Durable Subscriptions](durable-subscriptions.md). |
| `:start_from` | Requires `:durable`. |

The Bus monitors the target and removes the subscription when the target exits. A subscription ID that is already in use returns `{:error, :subscription_already_exists}`.

```elixir
alias Jido.Signal.Bus

{:ok, bus} = Bus.whereis(:ticket_events)

worker = spawn(fn -> Process.sleep(:infinity) end)

{:ok, "ticket-metrics"} = Bus.subscribe(bus, "ticket.**", target: worker, subscription_id: "ticket-metrics")
{:error, :subscription_already_exists} = Bus.subscribe(bus, "ticket.**", target: worker, subscription_id: "ticket-metrics")

:ok = Bus.unsubscribe(bus, "ticket-metrics")
{:error, :subscription_not_found} = Bus.unsubscribe(bus, "ticket-metrics")
Process.exit(worker, :kill)

{:error, {:unsupported_option, :timeout}} = Bus.subscribe(bus, "ticket.*", timeout: 100)
{:error, {:requires_option, :start_from, :durable}} = Bus.subscribe(bus, "ticket.*", start_from: :origin)
```

## Filter by source and subject

A `:selector` adds exact checks to the type path. It accepts `:source`, `:subject`, or both. All listed fields must equal the Signal's values, and letter case counts. A Signal with no subject never matches a selected subject.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :stock_events)

{:ok, _subscription} =
  Bus.subscribe(bus, "inventory.stock.changed",
    selector: [source: "/warehouses/east", subject: "sku-42"]
  )

east =
  Signal.new!("inventory.stock.changed", %{"quantity" => 7},
    source: "/warehouses/east",
    subject: "sku-42"
  )

west =
  Signal.new!("inventory.stock.changed", %{"quantity" => 1},
    source: "/warehouses/west",
    subject: "sku-42"
  )

{:ok, [_first, _second]} = Bus.publish(bus, [west, east])

^east =
  receive do
    {:signal, signal} -> signal
  after
    1_000 -> :timeout
  end

{:error, {:invalid_selector, _message}} = Bus.subscribe(bus, "inventory.*", selector: [])
{:error, {:invalid_selector, _message}} = Bus.subscribe(bus, "inventory.*", selector: [type: "x"])
{:error, {:conflicting_options, [:selector, :durable]}} =
  Bus.subscribe(bus, "inventory.*", selector: [subject: "sku-42"], durable: "stock-reader")
```

Each value is a non-empty string of at most 4,096 bytes. A source must be a valid URI-reference. Data and extension attributes cannot be selected on, and a selector cannot run your own function. To filter on those, check the Signal in the subscriber.

## Delivery order

Records reach subscribers in publication order. For one record, the Bus sends to subscriptions in Router order, so an exact path comes before `*`, which comes before `**`. A process with two matching subscriptions receives two messages.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :order_events)
{:ok, _wide} = Bus.subscribe(bus, "order.**")
{:ok, _narrow} = Bus.subscribe(bus, "order.placed")

signal = Signal.new!("order.placed", %{}, source: "/shop")
{:ok, [_record]} = Bus.publish(bus, [signal])

receive_signal = fn ->
  receive do
    {:signal, message} -> message
  after
    1_000 -> :timeout
  end
end

^signal = receive_signal.()
^signal = receive_signal.()
```

Delivery is a `send/2`. The Bus does not wait for the subscriber, and an ordinary subscriber gets no second chance if it exits before it handles a message. A subscriber that falls behind builds up its own mailbox.

## Replay retained records

`Jido.Signal.Bus.replay/3` reads the store. It sends no messages and does not affect subscriptions. Pass the path, `:after` for an exclusive cursor, and `:limit` for a positive count or `:infinity`. The default path is `**`. Replay does not accept `:selector`.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :audit_events)

{:ok, _records} =
  Bus.publish(bus, [
    Signal.new!("audit.login", %{"user" => "ana"}, source: "/auth"),
    Signal.new!("billing.charge", %{"user" => "ana"}, source: "/billing"),
    Signal.new!("audit.logout", %{"user" => "ana"}, source: "/auth")
  ])

{:ok, all} = Bus.replay(bus)
[1, 2, 3] = Enum.map(all, & &1.cursor)

{:ok, audit} = Bus.replay(bus, "audit.*")
["audit.login", "audit.logout"] = Enum.map(audit, & &1.type)

{:ok, [%{cursor: 3}]} = Bus.replay(bus, "audit.*", after: 1)
{:ok, [%{cursor: 1}]} = Bus.replay(bus, "audit.*", limit: 1)

{:error, {:unsupported_option, :selector}} = Bus.replay(bus, "audit.*", selector: [source: "/auth"])
{:error, {:invalid_option, :limit}} = Bus.replay(bus, "audit.*", limit: 0)
```

## Retention

`Jido.Signal.Bus.Store.Memory` keeps at most `:max_log_size` records. Past that limit, it removes the oldest records that no durable subscription still needs. Its contents do not survive a Bus or VM restart.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :recent_events, max_log_size: 2)

for number <- 1..3 do
  {:ok, _record} = Bus.publish(bus, [Signal.new!("job.finished", %{"number" => number}, source: "/jobs")])
end

{:ok, [%{cursor: 2}, %{cursor: 3}]} = Bus.replay(bus)
```

[Durable Subscriptions](durable-subscriptions.md) covers how durable consumers change retention, and how to supply a store that survives a restart.

## Isolate Buses

Set `:jido` to give each Instance or tenant its own Bus under the same name. A scoped Bus is not visible to a lookup without that scope, so get its PID with `Jido.Signal.Bus.whereis/2`. The `:bus` dispatch adapter takes the same option.

```elixir
alias Jido.Signal
alias Jido.Signal.{Bus, Dispatch}

{:ok, acme} = Bus.start_link(name: :tenant_events, jido: GuideBus.Acme)
{:ok, globex} = Bus.start_link(name: :tenant_events, jido: GuideBus.Globex)

true = acme != globex
{:ok, ^acme} = Bus.whereis(:tenant_events, jido: GuideBus.Acme)
{:error, :not_found} = Bus.whereis(:tenant_events)

signal = Signal.new!("ticket.opened", %{}, source: "/support")
:ok = Dispatch.dispatch(signal, {:bus, target: :tenant_events, jido: GuideBus.Acme})

{:ok, [%{signal: ^signal}]} = Bus.replay(acme)
{:ok, []} = Bus.replay(globex)
```

## Timeouts

Bus calls use a 30-second timeout, and return `{:error, :timeout}` when it expires while the Bus is alive. A store callback runs inside the Bus process, so a slow store delays all callers. Set another positive value with:

<!-- partial -->
```elixir
config :jido, Jido.Signal.Bus, call_timeout: 5_000
```

## Limits

- The Bus is local. A target must be a PID on the same node, or `Jido.Signal.Bus.subscribe/3` returns `{:error, :invalid_target}`.
- The Bus does not own retry timers, dead-letter queues, leases, or competing consumers.
- `publish/2` does not check `data` against a schema. See [Signal Data Schemas](signal-data-schemas.md).

The Bus emits telemetry for publish, delivery, and subscription changes. See [Telemetry Events](../reference/telemetry-event-reference.md).

## Next steps

- [Durable Subscriptions](durable-subscriptions.md) for at-least-once consumers.
- [Signal Bus Plugin](../built-in-plugins/signal-bus-plugin.livemd) to connect a Bus to an Agent.
- [Signal Dispatch Adapters](dispatch-adapters.md) to publish through the `:bus` adapter.
