# Custom Adapters

This guide shows how to implement `Jido.Persistence.Store` for a storage system that Jido does not ship an adapter for, then check it through the same paths the runtime uses.

An adapter stores binary keys and values. It knows nothing about Agents, revisions, or tombstones. Its one hard requirement is an atomic conditional write. If your storage cannot compare and replace one key atomically, it cannot back Jido persistence safely.

## Know the callbacks

| Callback | Required | Purpose |
| --- | --- | --- |
| `get/2` | Yes | Return one value, and optionally an opaque token |
| `compare_and_swap/4` | Yes | Write one value if the read condition still holds |
| `validate_options/1` | No | Check options before an operation starts |
| `delete/2` | No | Physically remove a key, for maintenance and Flow cleanup |
| `put/3` | No | Replace a value unconditionally, for explicit maintenance. Jido's own write paths do not call it |

`Jido.Persistence` validates the configuration on each operation, so keep `validate_options/1` cheap. Leave out `delete/2` only if you accept that [Flow execution records](flow-continuations.md) stay in storage after a Turn ends.

## Implement the behaviour

This adapter keeps a version number next to each value and uses it as the token. Real storage would have a version column, an ETag, or a generation number. A named process stands in for that storage so the example runs alone.

```elixir
defmodule CustomAdapterGuide.VersionedStore do
  @behaviour Jido.Persistence.Store

  def start_link(name), do: Agent.start_link(fn -> %{} end, name: name)

  @impl true
  def validate_options(opts) do
    if is_atom(opts[:server]) and not is_nil(opts[:server]),
      do: :ok,
      else: {:error, ":server must name a running store"}
  end

  @impl true
  def get(key, opts) do
    case Agent.get(opts[:server], &Map.get(&1, key)) do
      nil -> {:error, :not_found}
      {value, version} -> {:ok, value, Integer.to_string(version)}
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts) do
    Agent.get_and_update(opts[:server], fn records ->
      current = Map.get(records, key)

      if matches?(current, expected) do
        {:ok, Map.put(records, key, {value, next_version(current)})}
      else
        {{:error, :conflict}, records}
      end
    end)
  end

  @impl true
  def delete(key, opts), do: Agent.update(opts[:server], &Map.delete(&1, key))

  defp matches?(nil, :not_found), do: true
  defp matches?({_value, version}, {:token, token}), do: Integer.to_string(version) == token
  defp matches?(_current, _expected), do: false

  defp next_version(nil), do: 1
  defp next_version({_value, version}), do: version + 1
end

{:ok, _pid} = CustomAdapterGuide.VersionedStore.start_link(:custom_adapter_guide_store)

store = {CustomAdapterGuide.VersionedStore, server: :custom_adapter_guide_store}
```

The comparison and the write happen in one step inside the store. A separate read followed by a write would let two writers both succeed, and revision checks would no longer protect the record.

## Return the right read results

| `get/2` returns | Meaning | Condition for the next write |
| --- | --- | --- |
| `{:ok, bytes}` | Found | The exact bytes |
| `{:ok, bytes, token}` | Found, with a nonempty binary token | `{:token, token}` |
| `{:error, :not_found}` | Missing. Use this exact reason | `:not_found` |
| `{:error, reason}` | The read failed | None |

Return a token when comparing a full value is expensive, or when your storage already has a version. Otherwise return only the bytes. `compare_and_swap/4` then receives those bytes as `expected`, and must compare them exactly.

Any other return value becomes a `Jido.Error.ExecutionError` with `details.code` of `:persistence_invalid_callback_result`. A raise or exit becomes one with `:persistence_callback_failed`.

## Classify write results

The result of `compare_and_swap/4` tells the runtime whether storage may have changed.

| Return | Use it when |
| --- | --- |
| `:ok` | The write committed |
| `{:error, :conflict}` | The condition did not hold, and nothing was written |
| `{:error, {:rejected, reason}}` | Your code finished a check before the write started, such as a size limit. Nothing was written |
| `{:error, {:indeterminate, reason}}` | The write may have committed, such as a timeout or a lost reply |

`Jido.Persistence.Store.compare_and_swap/4` treats every other error, an invalid return, a raise, a throw, and an exit as indeterminate:

```elixir
defmodule CustomAdapterGuide.TimeoutStore do
  @behaviour Jido.Persistence.Store

  @impl true
  def get(_key, _opts), do: {:error, :not_found}

  @impl true
  def compare_and_swap(_key, _expected, _value, _opts), do: {:error, :timeout}
end

{:error, {:indeterminate, :timeout}} =
  Jido.Persistence.Store.compare_and_swap(
    {CustomAdapterGuide.TimeoutStore, []},
    "order-1",
    :not_found,
    "bytes"
  )
```

Do not retry a write inside the adapter after an uncertain failure. A retry can read the value from the first attempt and report a false conflict. Do not report `{:error, :conflict}` unless you know that no write happened.

## Check the byte contract

Call the adapter through `Jido.Persistence.Store`, as the runtime does. This sequence covers a missing key, a create, a stale token, and an update:

```elixir
{:ok, ^store} = Jido.Persistence.Store.open(store)

{:error, :not_found} = Jido.Persistence.Store.read(store, "order-1")
:ok = Jido.Persistence.Store.compare_and_swap(store, "order-1", :not_found, <<0, 255>>)
{:error, :conflict} = Jido.Persistence.Store.compare_and_swap(store, "order-1", :not_found, "late")

{:ok, <<0, 255>>, condition} = Jido.Persistence.Store.read(store, "order-1")
{:token, "1"} = condition

:ok = Jido.Persistence.Store.compare_and_swap(store, "order-1", condition, "second")
{:error, :conflict} = Jido.Persistence.Store.compare_and_swap(store, "order-1", condition, "stale")
{:ok, "second", {:token, "2"}} = Jido.Persistence.Store.read(store, "order-1")
```

Use arbitrary bytes in your tests, including `<<0, 255>>`. Jido's record bytes are not text, so a column or client that expects UTF-8 will fail on real records.

Next, prove that one writer wins a race. Concurrent writers with the same condition must produce one `:ok` and the rest `{:error, :conflict}`:

```elixir
{:ok, _bytes, race_condition} = Jido.Persistence.Store.read(store, "order-1")

results =
  1..8
  |> Task.async_stream(
    &Jido.Persistence.Store.compare_and_swap(store, "order-1", race_condition, <<&1>>),
    max_concurrency: 8
  )
  |> Enum.map(fn {:ok, result} -> result end)
  |> Enum.frequencies()

%{:ok => 1, {:error, :conflict} => 7} = results
```

Run this race against the real storage system. An in-process stand-in cannot expose a backend that lacks atomic writes.

Invalid options and an incomplete module fail when the configuration opens:

```elixir
{:error, {:invalid_persistence_options, CustomAdapterGuide.VersionedStore, _reason}} =
  Jido.Persistence.Store.open({CustomAdapterGuide.VersionedStore, []})

{:error, {:invalid_persistence_adapter, String}} = Jido.Persistence.Store.open(String)
```

Jido has no public conformance helper for third-party adapters, so keep these checks in your own test suite.

## Run an Agent on the adapter

Once the byte contract holds, the rest of persistence works without further code. This example runs revisions, restore, and tombstones through the new adapter:

```elixir
defmodule CustomAdapterGuide.ApplyRefund do
  use Jido.Action,
    name: "custom_adapter_guide_apply_refund",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  @impl true
  def run(%{cents: cents}, %{agent_state: state}),
    do: {:ok, %{state | refunded_cents: state.refunded_cents + cents}}
end

defmodule CustomAdapterGuide.Order do
  use Jido.Agent, name: "custom_adapter_guide_order"

  state do
    schema Jido.Joi.object(%{refunded_cents: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    route "order.refund", CustomAdapterGuide.ApplyRefund
  end
end

{:ok, _instance} =
  Jido.start_link(name: CustomAdapterGuide.Jido, namespace: "orders", persistence: store)

{:ok, order} =
  Jido.start_agent(CustomAdapterGuide.Jido, CustomAdapterGuide.Order,
    id: "order-1001",
    persistence: :inherit
  )

:ok = Jido.AgentServer.await_ready(order)

refund = Jido.Signal.new!("order.refund", %{cents: 700}, source: "/orders")
{:ok, _agent, _directives} = Jido.AgentServer.call(order, refund)
:ok = Jido.hibernate(CustomAdapterGuide.Jido, order)

{:ok, %{state: %{refunded_cents: 700}}, 1} =
  Jido.Persistence.load_agent_with_revision(
    CustomAdapterGuide.Jido,
    CustomAdapterGuide.Order,
    "order-1001"
  )

:ok =
  Jido.Persistence.delete_agent(
    CustomAdapterGuide.Jido,
    CustomAdapterGuide.Order,
    "order-1001"
  )

{:error, :deleted} =
  Jido.Persistence.load_agent(
    CustomAdapterGuide.Jido,
    CustomAdapterGuide.Order,
    "order-1001"
  )
```

## Plan for size and write rate

Records hold complete Agents, so their size follows Agent state and definition size. Reject oversized values before the write starts with `{:error, {:rejected, reason}}`, as the shipped adapters do. A size limit found after the write starts is an indeterminate result.

A Flow Turn writes several keys per step, so the write rate of a durable Flow is higher than the Turn rate. See [Continuation Storage](flow-continuations.md).

Keep credentials, values, and tokens out of your adapter's logs. Jido's own store telemetry reports only the operation, adapter module, and status.

## Related

- [Storage Model](persistence-storage-model.md): what the bytes contain.
- [Redis and S3 Stores](redis-and-s3-persistence.md): two shipped adapters built around a host-supplied function, which may suit your backend with less code.
