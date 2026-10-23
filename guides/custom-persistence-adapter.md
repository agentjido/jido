# Custom Adapters

Implement `Jido.Persistence.Adapter` to store Agent records in a backend that
Jido doesn't ship. An adapter is a byte store with one atomic operation:
compare-and-swap. Jido builds records, checks revisions and writes tombstones
itself. Your adapter moves bytes and reports what happened.

This guide builds an in-memory adapter on an Elixir `Agent` process, runs a
durable Jido Agent on it, and lists the checks your adapter must pass.

## The Adapter

```elixir
defmodule MyApp.MemoryAdapter do
  @moduledoc "Stores Jido records in one supervised process."
  @behaviour Jido.Persistence.Adapter

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)
    %{id: {__MODULE__, name}, start: {Agent, :start_link, [fn -> %{} end, [name: name]]}}
  end

  @impl true
  def validate_options(opts) do
    case Keyword.get(opts, :name) do
      name when is_atom(name) and name != nil -> :ok
      _ -> {:error, ":name must be the registered adapter process"}
    end
  end

  @impl true
  def get(key, opts) do
    case Agent.get(opts[:name], &Map.fetch(&1, key)) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :not_found}
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts) do
    Agent.get_and_update(opts[:name], fn records ->
      if Map.get(records, key, :not_found) == expected,
        do: {:ok, Map.put(records, key, value)},
        else: {{:error, :conflict}, records}
    end)
  end

  @impl true
  def put(key, value, opts), do: Agent.update(opts[:name], &Map.put(&1, key, value))

  @impl true
  def delete(key, opts), do: Agent.update(opts[:name], &Map.delete(&1, key))
end
```

`Agent.get_and_update/2` runs the comparison and the write in one process
step, so no other write can land between them. That makes the
compare-and-swap atomic.

## The Callbacks

| Callback | Required | Jido calls it | Returns |
| --- | --- | --- | --- |
| `validate_options/1` | No | Each time Jido resolves a store: instance start, Agent start, each Server save, each `Jido.Persistence` call. Keep it fast. | `:ok` or `{:error, reason}` |
| `get/2` | Yes | Before each save after revision 0, on load, thaw and delete | `{:ok, value}`, `{:ok, value, token}` or `{:error, :not_found}` |
| `compare_and_swap/4` | Yes | For each record write: revision 0, each Turn, hibernate, tombstones | `:ok`, `{:error, :conflict}` or another error |
| `put/3` | No | Never during a Turn; only for maintenance you run | `:ok` or `{:error, reason}` |
| `delete/2` | No | Never during a Turn; only for maintenance you run | `:ok` or `{:error, reason}` |

Keys and values are binaries. Don't decode either one. The key format and
record layout are in [Storage Model](persistence-storage-model.md).

A module that doesn't export `get/2` and `compare_and_swap/4` fails with
`{:error, {:invalid_persistence_adapter, module}}`. A `validate_options/1`
error becomes
`{:error, {:invalid_persistence_options, module, reason}}`:

```elixir
Jido.Persistence.Store.open({MyApp.MemoryAdapter, []})
# => {:error,
#     {:invalid_persistence_options, MyApp.MemoryAdapter,
#      ":name must be the registered adapter process"}}
```

## Run an Agent on It

```elixir
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app/counter")

    route "counter.add", as: :add, defaults: %{amount: 1} do
      action %{amount: amount},
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end
end

store = {MyApp.MemoryAdapter, name: MyApp.Records}

{:ok, _} =
  Supervisor.start_link(
    [
      {MyApp.MemoryAdapter, name: MyApp.Records},
      {Jido, name: MyApp.Jido, namespace: "my-app", persistence: store}
    ],
    strategy: :one_for_one
  )
```

Start the adapter process before the Jido instance. Jido doesn't start or
supervise adapter processes.

**Create.** The first start writes revision 0 with `compare_and_swap/4` and
`:not_found` as the expected value:

```elixir
{:ok, pid} = Jido.start_agent(MyApp.Jido, MyApp.Counter, id: "counter-1", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(pid)

Jido.AgentServer.snapshot(pid).state_version
# => 0
```

**Save.** Each Turn reads the record with `get/2`, then writes revision + 1
with the bytes it read as the expected value:

```elixir
signal = MyApp.Counter.add_signal!(%{amount: 5})
{:ok, _agent, []} = Jido.AgentServer.call(pid, signal)

Jido.AgentServer.snapshot(pid).state_version
# => 1
```

**Restore.** Hibernate the Agent, then thaw it from the adapter:

```elixir
ref = Process.monitor(pid)
:ok = Jido.hibernate(MyApp.Jido, pid)
receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)

{:ok, pid} = Jido.thaw(MyApp.Jido, MyApp.Counter, "counter-1")
:ok = Jido.AgentServer.await_ready(pid)

snapshot = Jido.AgentServer.snapshot(pid)
{snapshot.agent.state, snapshot.state_version}
# => {%{count: 5}, 1}
```

**Conflict.** Another writer moves the record to revision 2 while the Server
holds revision 1:

```elixir
{:ok, current} = Jido.Persistence.load_agent(MyApp.Jido, MyApp.Counter, "counter-1")
:ok = Jido.Persistence.save_agent(MyApp.Jido, current, revision: 2, expected_revision: 1)

ref = Process.monitor(pid)
{:error, error} = Jido.AgentServer.call(pid, signal)
error.message
# => "Required durable commit failed"
error.details
# => %{reason: :conflict}

receive do: ({:DOWN, ^ref, :process, ^pid, reason} -> reason)
# => {:shutdown, :execution_lifecycle_failed}
```

The Server's next save reads revision 2 where it expects 1, so it fails
with `:conflict` before it writes. When two writers race between the read
and the write, your `compare_and_swap/4` is what catches it: the loser's
expected bytes no longer match. Either way, the Turn doesn't commit and the
activation ends. Thaw the Agent to continue
from the stored revision. See
[Revisions and Conflicts](durable-revisions-and-conflicts.md).

## Required Semantics

### Atomic Compare-and-Swap

`expected` is one of:

| Expected | Write only when |
| --- | --- |
| `:not_found` | The key is absent |
| A binary | The stored bytes equal it exactly |
| `{:token, token}` | Your adapter's token from the last `get/2` still holds |

The comparison and the write must be one atomic step relative to every other
write and delete on that key. A `get/2` followed by a `put/3` isn't enough:
two Servers could both read revision 4 and both write revision 5. Use the
backend's own primitive: a transaction, a conditional `UPDATE`, a Lua script,
or a conditional `PUT`.

On a mismatch, return `{:error, :conflict}` and store nothing.

### Tokens

When the backend has a version, ETag or sequence number, return it from
`get/2` as `{:ok, value, token}`. Jido then passes `{:token, token}` to the
next `compare_and_swap/4` for that key, and you compare versions instead of
bytes:

```elixir
def get(key, opts) do
  case Agent.get(opts[:name], &Map.fetch(&1, key)) do
    {:ok, {version, value}} -> {:ok, value, Integer.to_string(version)}
    :error -> {:error, :not_found}
  end
end

def compare_and_swap(key, expected, value, opts) do
  Agent.get_and_update(opts[:name], fn records ->
    current = Map.get(records, key)

    if version_matches?(current, expected) do
      version = if current, do: elem(current, 0) + 1, else: 1
      {:ok, Map.put(records, key, {version, value})}
    else
      {{:error, :conflict}, records}
    end
  end)
end

defp version_matches?(nil, :not_found), do: true
defp version_matches?({version, _}, {:token, token}), do: token == Integer.to_string(version)
defp version_matches?(_current, _expected), do: false
```

A token must be a nonempty binary. Jido treats it as opaque and never stores
it. An adapter that returns `{:ok, value}` never receives a token.

### Uncertain Writes

Jido sorts every `compare_and_swap/4` result into one of four outcomes:

| Your result | Meaning | Server action |
| --- | --- | --- |
| `:ok` | Written | Commit the Turn |
| `{:error, :conflict}` | Not written; the expected value didn't match | End the activation |
| `{:error, {:rejected, reason}}` | Not written; a check failed before any write started | End the activation |
| `{:error, :indeterminate}` or `{:error, {:indeterminate, reason}}` | Unknown | End the activation |

Any other error, a raise, a throw, an exit, or a result outside this table
is treated as indeterminate. Return `:conflict` or `{:rejected, reason}`
only when you know nothing was written. A network timeout after the request
was sent is indeterminate: the write may have landed.

Don't retry a write inside the adapter after an unknown result. A retry can
find its own first write and report a false conflict. The record owner
reloads and decides.

### Timeouts

Bound every backend call. The Server waits up to `persistence_timeout:`
(default 5,000 ms) for a save. When that expires, the activation ends as
indeterminate, and Jido can't cancel a request your adapter already sent.
Set your client timeout below that budget and return
`{:error, {:indeterminate, :timeout}}` when a write's reply is lost.

### Tombstones

Your adapter doesn't implement tombstones. `Jido.Persistence.delete_agent/4`
writes a tombstone record with `compare_and_swap/4` like any other record.
`delete/2` physically removes a key. Jido calls it only from maintenance code
you write. Removing a tombstone lets a delayed writer recreate a deleted
Agent, so don't run it while any writer can use that key.

### Processes and Telemetry

The application supervises any process, pool or connection your adapter
uses. Every `get/2` and `compare_and_swap/4` call through the Store emits
`[:jido, :persistence, :store, :start]` and `[:jido, :persistence, :store, :stop]`
with the operation and adapter module. Keys, values and tokens never appear in
telemetry. Keep them out of your own logs too.

## What to Test

Run each check against a real instance of your backend, not a mock.

**Store checks**, through `Jido.Persistence.Store`:

1. `read/2` of a missing key returns `{:error, :not_found}`.
2. `compare_and_swap/4` with `:not_found` creates the key. A second create
   returns `{:error, :conflict}`.
3. `read/2` returns `{:ok, bytes, condition}`. A write with that condition
   succeeds once. The same condition fails the second time with
   `{:error, :conflict}`, and the stored bytes don't change.
4. Four concurrent writers with the same condition produce exactly one `:ok`
   and three `{:error, :conflict}`.

**Agent checks**, through an Agent Server:

1. A new Agent writes revision 0. Each Turn adds one, including a Turn that
   doesn't change state.
2. Hibernate, then thaw, keeps the state and the revision.
3. Thaw of an ID with no record stops the Server with
   `{:shutdown, :not_found}`.
4. After `delete_agent/4`, `load_agent/4` returns `{:error, :deleted}` and a
   delayed `save_agent/3` returns `{:error, :conflict}`.

**Failure checks**, with fault injection in your client:

1. A lost write reply returns indeterminate, never `:conflict`.
2. A slow backend returns before `persistence_timeout:`.

A minimal ExUnit test for the concurrency check:

```elixir
defmodule MyApp.MemoryAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Persistence.Store

  setup do
    name = :"records_#{System.unique_integer([:positive])}"
    start_supervised!({MyApp.MemoryAdapter, name: name})
    {:ok, store} = Store.open({MyApp.MemoryAdapter, name: name})
    %{store: store}
  end

  test "one of four concurrent writers wins", %{store: store} do
    :ok = Store.compare_and_swap(store, "key", :not_found, "v0")
    {:ok, "v0", condition} = Store.read(store, "key")

    results =
      1..4
      |> Task.async_stream(fn n -> Store.compare_and_swap(store, "key", condition, "v#{n}") end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 3
  end
end
```

## Next

- [Persistence Adapters](persistence-adapters.livemd) – the built-in adapters
  and their options.
- [Durability Model](durability-model.md) – what Jido guarantees with a
  correct adapter.
- [Testing](test-jido-systems.livemd) – test Agents that use persistence.
