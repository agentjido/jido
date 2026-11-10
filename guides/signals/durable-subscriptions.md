# Durable Subscriptions

Build a `Jido.Signal.Bus` consumer that keeps its place across process exits and handles each record at least once. A durable subscription has a stable string ID, a stored cursor, and one record in flight at a time.

Read [Signal Bus](signal-bus-and-subscriptions.md) first. It covers publishing, paths, and ordinary subscriptions.

## Receive and acknowledge

Pass `durable: id` to `Jido.Signal.Bus.subscribe/3`. The result is `{:ok, id}`, and the target receives `{:signal, id, record}`, where `record` is a `Jido.Signal.Bus.RecordedSignal`.

The Bus sends the next record only after the target calls `Jido.Signal.Bus.ack/3` with the current record's cursor.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :invoice_events)

invoice = fn number ->
  Signal.new!("invoice.issued", %{"number" => number}, source: "/billing")
end

{:ok, _records} = Bus.publish(bus, [invoice.("INV-1"), invoice.("INV-2")])

{:ok, "invoice-mailer"} =
  Bus.subscribe(bus, "invoice.*", durable: "invoice-mailer", start_from: :origin)

first =
  receive do
    {:signal, "invoice-mailer", record} -> record
  after
    1_000 -> :timeout
  end

1 = first.cursor
"INV-1" = first.signal.data["number"]

:only_one_in_flight =
  receive do
    {:signal, "invoice-mailer", _record} -> :unexpected
  after
    100 -> :only_one_in_flight
  end

:ok = Bus.ack(bus, "invoice-mailer", first.cursor)

second =
  receive do
    {:signal, "invoice-mailer", record} -> record
  after
    1_000 -> :timeout
  end

2 = second.cursor
:ok = Bus.ack(bus, "invoice-mailer", second.cursor)
```

Records that do not match the path do not hold the consumer back. The next delivery is the next matching record.

## Choose where to start

`:start_from` sets the first cursor when the subscription is created. Delivery starts after that cursor.

| Value | Behavior |
| --- | --- |
| `:current` | The default. Only records published after this call. |
| `:origin` | Everything retained. |
| A cursor | Records after that cursor. It must be from 0 up to the latest cursor, or the call returns `{:error, {:invalid_option, :start_from}}`. |

The Bus reads `:start_from` only on creation. When the ID already exists, the stored cursor wins and the option is ignored.

```elixir
alias Jido.Signal.Bus

{:ok, bus} = Bus.whereis(:invoice_events)

{:ok, "invoice-archive"} = Bus.subscribe(bus, "invoice.*", durable: "invoice-archive", start_from: 1)

2 =
  receive do
    {:signal, "invoice-archive", record} -> record.cursor
  after
    1_000 -> :timeout
  end

{:error, {:invalid_option, :start_from}} =
  Bus.subscribe(bus, "invoice.*", durable: "invoice-report", start_from: 99)

:ok = Bus.delete_subscription(bus, "invoice-archive")
```

## Write a consumer process

Run the consumer as a GenServer under a supervisor. Do the work, then acknowledge. The Bus sends no further record until the `ack`, so this process handles one record at a time.

`ack/3` must come from the target process.

```elixir
defmodule GuideDurable.InvoiceMailer do
  use GenServer

  alias Jido.Signal.Bus

  @durable_id "invoice-sender"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    bus = Keyword.fetch!(opts, :bus)
    {:ok, @durable_id} = Bus.subscribe(bus, "invoice.*", durable: @durable_id, start_from: :origin)
    {:ok, %{bus: bus, notify: Keyword.fetch!(opts, :notify)}}
  end

  @impl true
  def handle_info({:signal, @durable_id, record}, state) do
    send(state.notify, {:mailed, record.signal.data["number"]})
    :ok = Bus.ack(state.bus, @durable_id, record.cursor)
    {:noreply, state}
  end
end

alias GuideDurable.InvoiceMailer
alias Jido.Signal.Bus

{:ok, bus} = Bus.whereis(:invoice_events)
{:ok, mailer} = InvoiceMailer.start_link(bus: bus, notify: self())

mailed = fn ->
  receive do
    {:mailed, number} -> number
  after
    1_000 -> :timeout
  end
end

"INV-1" = mailed.()
"INV-2" = mailed.()

:ok = GenServer.stop(mailer)
```

If `Jido.Signal.Bus.subscribe/3` returns `{:error, :subscription_in_use}` in `init/1`, the old process is still attached. See [Attach rules](#attach-rules).

## Recover after an exit

When the target exits, the Bus keeps the subscription and its cursor. The record that was in flight is not acknowledged, so the Bus sends it again to the next process that attaches with the same ID.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :refund_events)
signal = Signal.new!("refund.requested", %{"refund_id" => "r-5"}, source: "/billing")
{:ok, [%{cursor: 1}]} = Bus.publish(bus, [signal])

parent = self()

{crashed, monitor} =
  spawn_monitor(fn ->
    {:ok, "refund-worker"} =
      Bus.subscribe(bus, "refund.*", durable: "refund-worker", start_from: :origin)

    receive do
      {:signal, "refund-worker", record} -> send(parent, {:started, record.cursor})
    end

    exit(:crashed_before_ack)
  end)

1 =
  receive do
    {:started, cursor} -> cursor
  after
    1_000 -> :timeout
  end

:crashed_before_ack =
  receive do
    {:DOWN, ^monitor, :process, ^crashed, reason} -> reason
  after
    1_000 -> :timeout
  end

{:ok, "refund-worker"} = Bus.subscribe(bus, "refund.*", durable: "refund-worker")

redelivered =
  receive do
    {:signal, "refund-worker", record} -> record
  after
    1_000 -> :timeout
  end

1 = redelivered.cursor
^signal = redelivered.signal
:ok = Bus.ack(bus, "refund-worker", redelivered.cursor)
```

Delivery is at least once. A process can do the work and exit before its `ack`, so the same record arrives again. Make the work idempotent, and use `record.signal.id` or `record.cursor` as the key.

## Attach rules

| Situation | Result |
| --- | --- |
| New ID | Creates the subscription and attaches the target. |
| Same ID, no live target | Attaches and resumes from the stored cursor. |
| Same ID, same target | Returns `{:ok, id}`. |
| Same ID, another live target | `{:error, :subscription_in_use}` |
| Same ID, different path | `{:error, :durable_subscription_conflict}` |
| ID used by an ordinary subscription | `{:error, :subscription_already_exists}` |

There is one target at a time. The Bus has no competing-consumer mode, leases, retry timers, or dead-letter queue. To retry a failed record, keep it in the consumer and `ack` when it finally succeeds or when you give up.

`:durable` cannot be combined with `:selector` or `:subscription_id`. A durable subscription selects by type path only.

## Acknowledgement errors

`Jido.Signal.Bus.ack/3` checks the owner and the cursor.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :shipment_events)
{:ok, [%{cursor: 1}]} = Bus.publish(bus, [Signal.new!("shipment.sent", %{}, source: "/shipping")])
{:ok, "shipment-tracker"} = Bus.subscribe(bus, "shipment.*", durable: "shipment-tracker", start_from: :origin)
{:ok, ordinary} = Bus.subscribe(bus, "shipment.*")

{:error, :subscription_not_found} = Bus.ack(bus, "missing", 1)
{:error, :subscription_not_durable} = Bus.ack(bus, ordinary, 1)
{:error, {:unexpected_cursor, 1}} = Bus.ack(bus, "shipment-tracker", 2)
{:error, :invalid_cursor} = Bus.ack(bus, "shipment-tracker", :latest)

{:error, :not_subscription_owner} =
  Task.await(Task.async(fn -> Bus.ack(bus, "shipment-tracker", 1) end))

:ok = Bus.ack(bus, "shipment-tracker", 1)
{:error, :no_record_in_flight} = Bus.ack(bus, "shipment-tracker", 1)
```

## Detach or delete

`Jido.Signal.Bus.unsubscribe/3` detaches the target and keeps the cursor. Any unacknowledged record is sent again on the next attach. `Jido.Signal.Bus.delete_subscription/2` removes the definition and the cursor permanently.

```elixir
alias Jido.Signal.Bus

{:ok, bus} = Bus.whereis(:shipment_events)

:ok = Bus.unsubscribe(bus, "shipment-tracker")
{:ok, "shipment-tracker"} = Bus.subscribe(bus, "shipment.*", durable: "shipment-tracker")

:ok = Bus.delete_subscription(bus, "shipment-tracker")
{:error, :subscription_not_found} = Bus.delete_subscription(bus, "shipment-tracker")
```

## Retention and a full store

`Jido.Signal.Bus.Store.Memory` keeps every record that a durable subscription still needs, including one with no attached target. If the store cannot make room, `Jido.Signal.Bus.publish/2` fails, stores nothing, and names the subscriptions that hold the records.

```elixir
alias Jido.Signal
alias Jido.Signal.Bus

{:ok, bus} = Bus.start_link(name: :sensor_events, max_log_size: 2)
reading = fn -> Signal.new!("sensor.reading", %{}, source: "/sensors") end

{:ok, "sensor-archive"} = Bus.subscribe(bus, "sensor.*", durable: "sensor-archive")
{:ok, [_first, _second]} = Bus.publish(bus, [reading.(), reading.()])

{:error, {:store_error, :append, {:store_full, ["sensor-archive"]}}} = Bus.publish(bus, [reading.()])

:ok = Bus.delete_subscription(bus, "sensor-archive")
{:ok, [%{cursor: 3}]} = Bus.publish(bus, [reading.()])
```

Delete a durable subscription that is no longer in use. An abandoned one stops publication once the log reaches its limit. Watch for this error, and size `:max_log_size` for how far a consumer can fall behind.

## Keep records across a Bus restart

The included memory store loses everything when the Bus stops. To keep records and cursors, implement `Jido.Signal.Bus.Store` and pass it as `:store`. Only `Jido.Signal.Bus.Store.Memory` is included.

| Callback | Contract |
| --- | --- |
| `init(opts)` | Returns `{:ok, state}`. A failure stops the Bus from starting. |
| `append(records, state)` | Accepts all records or none. |
| `read(opts, state)` | Returns records after the exclusive `:after_cursor`, filtered by `:path` when set, up to `:limit`. |
| `latest_cursor(state)` | Returns the highest cursor, or 0. The Bus uses it to number new records. |
| `list_subscriptions(state)` | Returns durable definitions in creation order. |
| `put_subscription(subscription, state)` | Creates or updates a durable definition. |
| `delete_subscription(id, state)` | Removes a durable definition. |

Records and definitions are string-key maps with `"format_version" => 1`. Treat them as opaque values to store and return.

Store callbacks run inside the Bus process, so set a finite timeout on each external operation. A callback that raises or returns an unexpected value becomes `{:error, {:store_error, callback, reason}}`.

The example below keeps the state of the memory store in a separate process, so the state outlives the Bus. This shows the contract. It is not durable storage, since the state still dies with the VM. A production store writes to a database.

```elixir
defmodule GuideDurable.HeldStore do
  @behaviour Jido.Signal.Bus.Store

  alias Jido.Signal.Bus.Store.Memory

  @impl true
  def init(opts), do: {:ok, Keyword.fetch!(opts, :holder)}

  @impl true
  def append(records, holder), do: update(holder, &Memory.append(records, &1))

  @impl true
  def read(opts, holder), do: Agent.get(holder, &Memory.read(opts, &1))

  @impl true
  def latest_cursor(holder), do: Agent.get(holder, &Memory.latest_cursor/1)

  @impl true
  def list_subscriptions(holder), do: Agent.get(holder, &Memory.list_subscriptions/1)

  @impl true
  def put_subscription(subscription, holder), do: update(holder, &Memory.put_subscription(subscription, &1))

  @impl true
  def delete_subscription(id, holder), do: update(holder, &Memory.delete_subscription(id, &1))

  defp update(holder, operation) do
    Agent.get_and_update(holder, fn state ->
      case operation.(state) do
        {:ok, next_state} -> {{:ok, holder}, next_state}
        {:error, reason} -> {{:error, reason}, state}
      end
    end)
  end
end

alias GuideDurable.HeldStore
alias Jido.Signal
alias Jido.Signal.Bus
alias Jido.Signal.Bus.Store.Memory

{:ok, memory} = Memory.init([])
{:ok, holder} = Agent.start_link(fn -> memory end)
bus_options = [name: :payment_events, store: HeldStore, store_opts: [holder: holder]]

{:ok, bus} = Bus.start_link(bus_options)
payment = fn id -> Signal.new!("payment.settled", %{"payment_id" => id}, source: "/payments") end

{:ok, "payment-ledger"} = Bus.subscribe(bus, "payment.*", durable: "payment-ledger")
{:ok, [%{cursor: 1}, %{cursor: 2}]} = Bus.publish(bus, [payment.("p-1"), payment.("p-2")])

1 =
  receive do
    {:signal, "payment-ledger", record} -> record.cursor
  after
    1_000 -> :timeout
  end

:ok = Bus.ack(bus, "payment-ledger", 1)

2 =
  receive do
    {:signal, "payment-ledger", record} -> record.cursor
  after
    1_000 -> :timeout
  end

:ok = GenServer.stop(bus)

{:ok, restarted} = Bus.start_link(bus_options)
{:ok, [%{cursor: 1}, %{cursor: 2}]} = Bus.replay(restarted)

{:ok, "payment-ledger"} = Bus.subscribe(restarted, "payment.*", durable: "payment-ledger")

2 =
  receive do
    {:signal, "payment-ledger", record} -> record.cursor
  after
    1_000 -> :timeout
  end

:ok = Bus.ack(restarted, "payment-ledger", 2)
{:ok, [%{cursor: 3}]} = Bus.publish(restarted, [payment.("p-3")])
```

After the restart, the subscription has no target until a process attaches again. Its cursor came from the store, so record 2 returned and record 1 did not.

`:max_log_size` applies only to the memory store. A custom store owns its own retention.

## Related

- [Signal Bus](signal-bus-and-subscriptions.md) for ordinary subscriptions and replay.
- [Signal Bus Plugin](../built-in-plugins/signal-bus-plugin.livemd) to use a durable subscription from an Agent.
- [Telemetry Events](../reference/telemetry-event-reference.md) for the `ack` and `delivery_error` events.
