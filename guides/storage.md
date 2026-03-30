# Persistence & Storage

<!-- covers: jido.runtime_persistence.hibernate_thaw jido.runtime_persistence.storage_backends jido.thread_memory_identity.thread_journal jido.thread_memory_identity.memory_capability jido.thread_memory_identity.identity_capability -->

**After:** Your agents can survive restarts, hibernate on idle, and preserve conversation history.

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Storage.File, path: "priv/jido/storage"}
end

# Manual: Hibernate an agent (flushes thread, writes checkpoint)
:ok = MyApp.Jido.hibernate(agent)

# Manual: Thaw an agent (loads checkpoint, rehydrates thread)
{:ok, agent} = MyApp.Jido.thaw(MyAgent, "user-123")

# Automatic: InstanceManager hibernates on idle, thaws on demand
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")
```

This guide covers Jido's unified persistence system: checkpoints, thread journals, manual and automatic lifecycle management.

If you are still deciding whether your durable unit should be one agent or one
team, start with [Choosing a Runtime Pattern](runtime-patterns.md).

## Choosing Your Persistence Model

| Approach | When to Use | API |
|----------|-------------|-----|
| **Manual** | Explicit control over when to persist | `MyApp.Jido.hibernate/1`, `thaw/2` |
| **Automatic** | Idle-based lifecycle for per-user/entity agents | `InstanceManager.get/3` with `idle_timeout` |
| **Pod-managed topology** | Durable named teams with explicit reattachment after thaw | `Jido.Pod.get/3` or `InstanceManager.get/3` + `Jido.Pod.reconcile/2` |
| **None** | Stateless agents, cheap rebuilds, short-lived tasks | Skip storage config |

Both manual and automatic approaches use the same underlying `Jido.Storage` behaviour.

## Pods Use Ordinary Checkpoints

Pods do not introduce a separate storage contract.

- The pod agent persists its topology snapshot as ordinary plugin state under
  `agent.state[:__pod__]`
- Each durable node persists through its own `Jido.Agent.InstanceManager`
- Storage adapters such as `jido_ecto` keep working through the same checkpoint
  and thread APIs

The durability boundary is important:

- storage preserves the pod topology snapshot
- storage does not preserve a live `state.children` tree, PIDs, or monitors
- live pod mutations update the persisted topology snapshot first, then repair
  runtime shape with explicit stop/start work

So thaw works like this:

1. the pod agent thaws and immediately has its topology back
2. eager roots and missing ownership edges are repaired by calling `Jido.Pod.reconcile/2`
3. lazy roots or surviving nodes are reattached on demand via `Jido.Pod.ensure_node/3`

If a node stayed alive independently while the pod manager was hibernated, it
can show up in two different states:

- surviving root nodes are typically `:running` until the pod manager re-adopts them
- surviving owned descendants can remain `:adopted` if their logical owner never died
- surviving nested pod managers follow the same rule, then reconcile their own
  eager topology once they are reattached

`Jido.Pod.get/3` bundles the common path by calling
`Jido.Agent.InstanceManager.get/3` and then reconciling eager nodes for you.
Use the explicit two-step path when you need to inspect the restored topology
before reattachment.

If a running pod changes shape with `Jido.Pod.mutate/3`, that updated topology
is what later hibernate/thaw cycles restore. Storage still does not preserve a
live process tree; it preserves the pod's latest durable topology plus each
node's own durable agent state.

See [Pods](pods.md) and `test/examples/runtime/mutable_pod_runtime_test.exs`
for the manager-led runtime model and examples.

## Overview

Jido Storage provides a simple, composable persistence model built on two core concepts:

| Concept | Metaphor | Description |
|---------|----------|-------------|
| **Thread** | Journal | Append-only event log, source of truth for what happened |
| **Checkpoint** | Snapshot | Serialized agent state for fast resume |

The relationship:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Source of Truth                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                Thread (Journal)                            │  │
│  │  - Append-only entries with monotonic seq                 │  │
│  │  - What happened, in order                                │  │
│  │  - Replayable, auditable                                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼ projection                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                 Agent State (In-Memory)                    │  │
│  │  - Current computed state                                 │  │
│  │  - Includes state[:__thread__] reference                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼ checkpoint                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Checkpoint (Snapshot Store)                   │  │
│  │  - Serialized agent state (without full thread)           │  │
│  │  - Thread pointer: {thread_id, thread_rev}                │  │
│  │  - For fast resume                                        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Invariant

**Never persist the full Thread inside the Agent checkpoint.** Store a pointer instead:

```elixir
%{
  thread_id: "thread_abc123",
  thread_rev: 42
}
```

This prevents:

- Data duplication between checkpoint and journal
- Consistency drift when checkpoint and journal get out of sync
- Memory bloat in serialized checkpoints

### Modeling Late Metadata with Follow-Up Events

When metadata arrives after an entry has already been appended, record it as a
new fact instead of mutating the original entry.

This comes up often with external providers. For example, an assistant message
may be appended to the thread before Slack returns the final message `ts`. In
that case, supply a stable `entry_id` up front, then append a second entry that
points back to the original message by `entry_id`:

```elixir
alias Jido.Thread.Agent, as: ThreadAgent

entry_id = "entry_" <> Jido.Util.generate_id()

agent =
  ThreadAgent.append(agent, %{
    id: entry_id,
    kind: :message,
    payload: %{role: "assistant", content: "Working on it"}
  })

agent =
  ThreadAgent.append(agent, %{
    kind: :message_committed,
    payload: %{provider: :slack, remote_id: slack_ts},
    refs: %{entry_id: entry_id}
  })
```

You can also model this as a more generic annotation entry:

```elixir
agent =
  ThreadAgent.append(agent, %{
    kind: :annotation,
    payload: %{type: :provider_ref, provider: :slack, remote_id: slack_ts},
    refs: %{entry_id: entry_id}
  })
```

This keeps the journal canonical and append-only:

- The original message remains immutable
- Journal-backed storage and thawed agents see the same history
- Read models can fold follow-up events into a resolved "message plus provider metadata" view
- The same pattern works for retries, edits, deletes, delivery failures, and acknowledgements

### Scheduler Manifest Invariant

Dynamic cron durability is stored as a scheduler manifest under
`state[:__cron_specs__]` in checkpoints.

- Runtime-only thread state (`:__thread__`) is always stripped from checkpoint `state`
- Scheduler durability data is normalized and stored only under `:__cron_specs__`
- Manifest updates use targeted checkpoint patching when a checkpoint exists
- If no checkpoint exists yet, Jido falls back to a full `hibernate` write

This keeps dynamic scheduler durability consistent with the same storage and
checkpoint invariants used by the rest of Jido persistence.

### Terminology

| Operation | Description |
|-----------|-------------|
| **hibernate** | Flush journal, write checkpoint, persist agent for later |
| **thaw** | Load checkpoint, rehydrate thread, resume agent |
| **checkpoint** | Agent callback to serialize state |
| **restore** | Agent callback to deserialize state |

## Quick Start

### Default (ETS, Ephemeral)

With no configuration, Jido uses ETS storage (fast, in-memory, lost on restart):

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
  # Uses Jido.Storage.ETS by default
end

# Create an agent with a thread
{:ok, agent} = MyAgent.new(id: "user-123")
thread = Jido.Thread.new()
agent = put_in(agent.state[:__thread__], thread)

# Do some work, add entries to the thread...
thread = Jido.Thread.append(thread, :message, %{content: "Hello!"})
agent = put_in(agent.state[:__thread__], thread)

# Hibernate - agent can now be garbage collected
:ok = MyApp.Jido.hibernate(agent)

# Later... thaw the agent
{:ok, restored_agent} = MyApp.Jido.thaw(MyAgent, "user-123")
# restored_agent.state[:__thread__] is rehydrated with entries
```

### File-Based (Simple Production)

For persistence across restarts:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Storage.File, path: "priv/jido/storage"}
end

# Same API
:ok = MyApp.Jido.hibernate(agent)
{:ok, agent} = MyApp.Jido.thaw(MyAgent, "user-123")
```

## Configuration

Storage is configured per Jido instance via `use Jido`:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Storage.ETS, table: :my_storage}
end
```

Or just the module (options default to `[]`):

```elixir
storage: Jido.Storage.ETS
```

### Built-in Adapters

| Adapter | Durability | Use Case |
|---------|------------|----------|
| `Jido.Storage.ETS` | Ephemeral | Development, testing |
| `Jido.Storage.File` | Disk | Simple production |
| `Jido.Storage.Redis` | Durable | Optional external backing store |

### ETS Storage Options

```elixir
storage: {Jido.Storage.ETS, table: :my_jido_storage}
```

| Option | Default | Description |
|--------|---------|-------------|
| `:table` | `:jido_storage` | Base table name. Creates three ETS tables: `{table}_checkpoints`, `{table}_threads`, `{table}_thread_meta` |

### File Storage Options

```elixir
storage: {Jido.Storage.File, path: "priv/jido/storage"}
```

| Option | Default | Description |
|--------|---------|-------------|
| `:path` | (required) | Base directory path. Created automatically if it doesn't exist. |

Directory layout:

```
priv/jido/storage/
├── checkpoints/
│   └── {key_hash}.term       # Serialized checkpoint
└── threads/
    └── {thread_id}/
        ├── meta.term          # {rev, created_at, updated_at, metadata}
        └── entries.log        # Length-prefixed binary frames
```

### Redis Storage Options

```elixir
defmodule MyApp.RedisStorage do
  def command(cmd), do: Redix.command(:my_redis, cmd)
end

storage: {Jido.Storage.Redis, command_fn: &MyApp.RedisStorage.command/1}
```

| Option | Default | Description |
|--------|---------|-------------|
| `:command_fn` | (required) | A `fn [binary()] -> {:ok, term()} \| {:error, term()}` that executes Redis commands. Bring your own client (Redix, etc.). |
| `:prefix` | `"jido"` | Key prefix for namespacing. |
| `:ttl` | `nil` | TTL in milliseconds. When set, all keys expire automatically. |

Key layout:

```
{prefix}:cp:{hex_hash}   → Serialized checkpoint
{prefix}:th:{thread_id}  → Serialized thread state
```

Redis is one durable storage option when you already operate Redis and want a shared external store. Jido core does not add a Redis dependency; callers provide `:command_fn`. Thread state is stored in a single value to avoid partial writes between entries and metadata.

## API Reference

### High-Level API (Jido Instance)

When you `use Jido`, you get `hibernate/1` and `thaw/2` functions:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: {Jido.Storage.ETS, []}
end

# Hibernate an agent
:ok = MyApp.Jido.hibernate(agent)

# Thaw an agent by module and ID
{:ok, agent} = MyApp.Jido.thaw(MyAgent, "user-123")
```

### Instance-Level Durable Cron Semantics

When an agent runs under `Jido.Agent.InstanceManager` with storage enabled:

- Dynamic `Cron`/`CronCancel` directives are write-through durable via `Jido.Persist`
- Durability is keyed by `{manager_name, pool_key}` (instance-scoped)
- Acknowledged register/cancel mutations survive thaw and crash-restart recovery
- Missed runs are not replayed (no catch-up)

#### `hibernate/1`

Persists an agent to storage:

1. Extracts thread from `agent.state[:__thread__]`
2. Flushes thread entries to journal storage
3. Calls `agent_module.checkpoint/2` to serialize state
4. Stores checkpoint (with thread pointer, not full thread)

**Returns:**

- `:ok` — Successfully hibernated
- `{:error, reason}` — Failed to hibernate

#### `thaw/2`

Restores an agent from storage:

1. Loads checkpoint by `{agent_module, key}`
2. Calls `agent_module.restore/2` to deserialize
3. If checkpoint has thread pointer, loads and attaches thread
4. Verifies thread revision matches checkpoint pointer

**Returns:**

- `{:ok, agent}` — Successfully restored
- `:not_found` — No checkpoint exists for this key
- `{:error, :missing_thread}` — Checkpoint references a thread that doesn't exist
- `{:error, :thread_mismatch}` — Loaded thread.rev doesn't match checkpoint pointer

### Direct API (Jido.Persist)

For direct control without a Jido instance:

```elixir
storage = {Jido.Storage.ETS, table: :my_storage}

# Hibernate
:ok = Jido.Persist.hibernate(storage, agent)

# Thaw
{:ok, agent} = Jido.Persist.thaw(storage, MyAgent, "user-123")
```

Or pass a struct with a `:storage` field:

```elixir
jido_instance = %{storage: {Jido.Storage.ETS, []}}
:ok = Jido.Persist.hibernate(jido_instance, agent)
```

## How It Works

### Hibernate Flow

```
Agent (in memory)
       │
       ▼
┌──────────────────────────────────────────────────┐
│ 1. Extract thread from agent.state[:__thread__] │
│ 2. Flush thread to Journal Store                │
│ 3. Call agent_module.checkpoint/2               │
│    - Excludes full thread, includes pointer     │
│ 4. Write checkpoint to Snapshot Store           │
└──────────────────────────────────────────────────┘
       │
       ▼
    Persisted
```

The key insight: journal is flushed **before** checkpoint is written. This ensures the thread entries exist before any checkpoint references them.

### Thaw Flow

```
    Persisted
       │
       ▼
┌──────────────────────────────────────────────────┐
│ 1. Load checkpoint from Snapshot Store          │
│ 2. Call agent_module.restore/2                  │
│ 3. If checkpoint has thread pointer:            │
│    - Load thread from Journal Store             │
│    - Verify rev matches checkpoint pointer      │
│    - Attach to agent.state[:__thread__]         │
│ 4. Return hydrated agent                        │
└──────────────────────────────────────────────────┘
       │
       ▼
Agent (in memory)
```

### Thread Pointer Concept

The checkpoint stores a **pointer** to the thread, not the thread itself:

```elixir
# Checkpoint structure
%{
  version: 1,
  agent_module: MyAgent,
  id: "user-123",
  state: %{name: "Alice", status: :active},  # No __thread__ key!
  thread: %{id: "thread_abc123", rev: 42}     # Just a pointer
}
```

On thaw, the thread is loaded separately from the journal store and verified:

```elixir
# If checkpoint says thread.rev = 42, but stored thread has rev = 41
# → {:error, :thread_mismatch}
```

This catches consistency issues between checkpoint and journal.

## Agent Callbacks

Agents can customize serialization via two optional callbacks:

### `checkpoint/2`

Called during hibernate to serialize the agent:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    schema: [
      user_id: [type: :string, required: true],
      session_data: [type: :map, default: %{}],
      temp_cache: [type: :map, default: %{}]  # Don't persist this
    ]

  @impl true
  def checkpoint(agent, _ctx) do
    thread = agent.state[:__thread__]

    {:ok, %{
      version: 1,
      agent_module: __MODULE__,
      id: agent.id,
      # Exclude temp_cache and __thread__
      state: agent.state |> Map.drop([:__thread__, :temp_cache]),
      thread: thread && %{id: thread.id, rev: thread.rev}
    }}
  end
end
```

**Parameters:**

- `agent` — The agent struct to serialize
- `ctx` — Context map (currently empty, reserved for future use)

**Returns:**

- `{:ok, checkpoint_data}` — Map with version, agent_module, id, state, and thread pointer

### `restore/2`

Called during thaw to deserialize the agent:

```elixir
@impl true
def restore(data, _ctx) do
  case new(id: data[:id] || data["id"]) do
    {:ok, agent} ->
      state = data[:state] || data["state"] || %{}
      # Restore defaults for non-persisted fields
      restored_state = Map.merge(state, %{temp_cache: %{}})
      {:ok, %{agent | state: Map.merge(agent.state, restored_state)}}

    error ->
      error
  end
end
```

**Parameters:**

- `data` — The checkpoint data from storage
- `ctx` — Context map (currently empty)

**Returns:**

- `{:ok, agent}` — The restored agent struct

### Default Behavior

If you don't implement these callbacks, the default implementations:

1. `checkpoint/2` — Serializes the full agent state (minus `__thread__`) with a thread pointer
2. `restore/2` — Creates a new agent via `new/1` and merges the stored state

```elixir
# Default checkpoint
def checkpoint(agent, _ctx) do
  thread = agent.state[:__thread__]

  {:ok, %{
    version: 1,
    agent_module: __MODULE__,
    id: agent.id,
    state: Map.delete(agent.state, :__thread__),
    thread: thread && %{id: thread.id, rev: thread.rev}
  }}
end

# Default restore
def restore(data, _ctx) do
  case new(id: data[:id] || data["id"]) do
    {:ok, agent} ->
      state = data[:state] || data["state"] || %{}
      {:ok, %{agent | state: Map.merge(agent.state, state)}}
    error ->
      error
  end
end
```

### Schema Evolution

Handle version migrations in `restore/2`:

```elixir
@impl true
def restore(%{version: 1} = data, ctx) do
  # Migrate v1 → v2: add new preferences field
  migrated = %{data | version: 2}
  migrated = put_in(migrated[:state][:preferences], %{theme: :light})
  restore(migrated, ctx)
end

@impl true
def restore(%{version: 2} = data, _ctx) do
  {:ok, agent} = new(id: data.id)
  {:ok, %{agent | state: Map.merge(agent.state, data.state)}}
end
```

## Building Custom Storage Adapters

Implement the `Jido.Storage` behaviour for your backend:

```elixir
defmodule MyApp.Storage do
  @behaviour Jido.Storage

  # Checkpoint operations (key-value, overwrite semantics)

  @impl true
  def get_checkpoint(key, opts) do
    # Return {:ok, data} | :not_found | {:error, reason}
  end

  @impl true
  def put_checkpoint(key, data, opts) do
    # Return :ok | {:error, reason}
  end

  @impl true
  def delete_checkpoint(key, opts) do
    # Return :ok | {:error, reason}
  end

  # Journal operations (append-only, sequence ordering)

  @impl true
  def load_thread(thread_id, opts) do
    # Return {:ok, %Jido.Thread{}} | :not_found | {:error, reason}
  end

  @impl true
  def append_thread(thread_id, entries, opts) do
    # Handle opts[:expected_rev] for optimistic concurrency
    # Return {:ok, %Jido.Thread{}} | {:error, :conflict} | {:error, reason}
  end

  @impl true
  def delete_thread(thread_id, opts) do
    # Return :ok | {:error, reason}
  end
end
```

### Example: Ecto/Postgres Adapter

```elixir
# Ecto schemas
defmodule MyApp.Jido.Checkpoint do
  use Ecto.Schema

  schema "jido_checkpoints" do
    field :key, :string
    field :agent_module, :string
    field :data, :map
    field :thread_id, :string
    field :thread_rev, :integer
    timestamps()
  end
end

defmodule MyApp.Jido.ThreadEntry do
  use Ecto.Schema

  schema "jido_thread_entries" do
    field :thread_id, :string
    field :seq, :integer
    field :kind, :string
    field :at, :integer
    field :payload, :map
    field :refs, :map
    timestamps()
  end
end

# Storage adapter
defmodule MyApp.JidoStorage do
  @behaviour Jido.Storage

  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Jido.{Checkpoint, ThreadEntry}
  alias Jido.Thread
  alias Jido.Thread.Entry

  # Checkpoint operations

  @impl true
  def get_checkpoint(key, _opts) do
    case Repo.get_by(Checkpoint, key: serialize_key(key)) do
      nil -> :not_found
      record -> {:ok, record.data}
    end
  end

  @impl true
  def put_checkpoint(key, data, _opts) do
    Repo.insert!(
      %Checkpoint{key: serialize_key(key), data: data},
      on_conflict: {:replace, [:data, :updated_at]},
      conflict_target: :key
    )
    :ok
  end

  @impl true
  def delete_checkpoint(key, _opts) do
    Repo.delete_all(from c in Checkpoint, where: c.key == ^serialize_key(key))
    :ok
  end

  # Journal operations

  @impl true
  def load_thread(thread_id, _opts) do
    entries =
      from(e in ThreadEntry, where: e.thread_id == ^thread_id, order_by: e.seq)
      |> Repo.all()
      |> Enum.map(&record_to_entry/1)

    case entries do
      [] -> :not_found
      entries -> {:ok, reconstruct_thread(thread_id, entries)}
    end
  end

  @impl true
  def append_thread(thread_id, entries, opts) do
    expected_rev = Keyword.get(opts, :expected_rev)

    Repo.transaction(fn ->
      current_max = get_max_seq(thread_id)

      # Optimistic concurrency check
      if expected_rev && current_max + 1 != expected_rev do
        Repo.rollback(:conflict)
      end

      entries
      |> Enum.with_index(current_max + 1)
      |> Enum.each(fn {entry, seq} ->
        Repo.insert!(%ThreadEntry{
          thread_id: thread_id,
          seq: seq,
          kind: to_string(entry.kind),
          at: entry.at,
          payload: entry.payload,
          refs: entry.refs
        })
      end)

      {:ok, _} = load_thread(thread_id, [])
    end)
  end

  @impl true
  def delete_thread(thread_id, _opts) do
    Repo.delete_all(from e in ThreadEntry, where: e.thread_id == ^thread_id)
    :ok
  end

  # Private helpers

  defp serialize_key({module, id}), do: "#{module}:#{id}"

  defp get_max_seq(thread_id) do
    from(e in ThreadEntry, where: e.thread_id == ^thread_id, select: max(e.seq))
    |> Repo.one() || -1
  end

  defp record_to_entry(record) do
    %Entry{
      id: "entry_#{record.id}",
      seq: record.seq,
      at: record.at,
      kind: String.to_existing_atom(record.kind),
      payload: record.payload || %{},
      refs: record.refs || %{}
    }
  end

  defp reconstruct_thread(thread_id, entries) do
    %Thread{
      id: thread_id,
      rev: length(entries),
      entries: entries,
      created_at: List.first(entries).at,
      updated_at: List.last(entries).at,
      metadata: %{},
      stats: %{entry_count: length(entries)}
    }
  end
end
```

Configure it:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    storage: MyApp.JidoStorage
end
```

### Ash Framework Adapter

For Ash, create a similar adapter using `Ash.read/2` and `Ash.create/2` instead of Ecto queries. The pattern is identical—implement the `Jido.Storage` behaviour.

### Testing Your Adapter

```elixir
defmodule MyApp.JidoStorageTest do
  use ExUnit.Case

  alias Jido.Thread
  alias Jido.Thread.Entry

  @storage {MyApp.JidoStorage, []}

  describe "checkpoints" do
    test "put and get" do
      key = {TestAgent, "test-123"}
      data = %{version: 1, id: "test-123", state: %{foo: "bar"}}

      assert :ok = MyApp.JidoStorage.put_checkpoint(key, data, [])
      assert {:ok, ^data} = MyApp.JidoStorage.get_checkpoint(key, [])
    end

    test "not found" do
      assert :not_found = MyApp.JidoStorage.get_checkpoint({TestAgent, "missing"}, [])
    end
  end

  describe "threads" do
    test "append and load" do
      thread_id = "thread_#{System.unique_integer()}"
      entries = [%Entry{kind: :message, payload: %{text: "hello"}}]

      assert {:ok, thread} = MyApp.JidoStorage.append_thread(thread_id, entries, [])
      assert thread.rev == 1
      assert length(thread.entries) == 1

      assert {:ok, loaded} = MyApp.JidoStorage.load_thread(thread_id, [])
      assert loaded.rev == 1
    end

    test "optimistic concurrency" do
      thread_id = "thread_#{System.unique_integer()}"
      entries = [%Entry{kind: :message, payload: %{}}]

      # First append succeeds
      {:ok, _} = MyApp.JidoStorage.append_thread(thread_id, entries, expected_rev: 0)

      # Second append with wrong expected_rev fails
      assert {:error, :conflict} =
        MyApp.JidoStorage.append_thread(thread_id, entries, expected_rev: 0)
    end
  end
end
```

## Production Patterns

### Optimistic Concurrency with `expected_rev`

The `append_thread/3` callback accepts an `:expected_rev` option:

```elixir
# Only append if current rev is 5
case adapter.append_thread(thread_id, entries, expected_rev: 5) do
  {:ok, thread} -> # Success, thread now at rev 6+
  {:error, :conflict} -> # Someone else appended first
end
```

This enables safe concurrent access. The ETS and File adapters both support this.

### Handling Thread Mismatches

When thaw returns `{:error, :thread_mismatch}`:

```elixir
case MyApp.Jido.thaw(MyAgent, "user-123") do
  {:ok, agent} ->
    agent

  {:error, :thread_mismatch} ->
    # Checkpoint and journal are out of sync
    # Options:
    # 1. Delete checkpoint and start fresh
    # 2. Load thread only and rebuild agent
    # 3. Alert ops team for investigation
    Logger.error("Thread mismatch for user-123")
    {:ok, agent} = MyAgent.new(id: "user-123")
    agent

  :not_found ->
    {:ok, agent} = MyAgent.new(id: "user-123")
    agent
end
```

### Thread Memory Management

For long-running agents, threads can grow large. Future enhancements will include:

- `load_thread_tail/3` — Load only the last N entries
- Thread compaction — Snapshot and truncate old entries

For now, consider periodic cleanup in your domain logic.

## Consistency Guardrails

| Problem | Solution |
|---------|----------|
| **Snapshot/Journal mismatch** | Coordinator flushes journal before checkpoint; stores `thread_rev` in checkpoint for verification on thaw |
| **Optimistic concurrency** | `expected_rev` option in `append_thread` — adapter rejects if current rev doesn't match |
| **Thread memory bloat** | Never persist full thread in checkpoint; future: `load_thread_tail` for bounded loading |

## Automatic Lifecycle with InstanceManager

For per-user or per-entity agents, `Jido.Agent.InstanceManager` provides automatic hibernate/thaw based on idle timeouts.

### Configuration

```elixir
# In your supervision tree
children = [
  Jido.Agent.InstanceManager.child_spec(
    name: :sessions,
    agent: MyApp.SessionAgent,
    idle_timeout: :timer.minutes(15),
    storage: {Jido.Storage.File, path: "priv/sessions"}
  )
]
```

`InstanceManager` storage resolution:

- `storage: {Adapter, opts}` or `storage: Adapter` - explicit backend override
- `storage` omitted - uses the configured Jido instance storage (`jido.__jido_storage__/0` when available)
- `storage: nil` - disables hibernate/thaw for that manager

This automatic lifecycle is scoped to agents started through
`Jido.Agent.InstanceManager`. It does not apply to arbitrary `SpawnAgent`
children, and hibernating a parent agent does not recursively persist its live
child tree. If a durable parent needs durable collaborators, model those
collaborators as keyed managed agents and reacquire or adopt them explicitly
after thaw.

```elixir
# Uses MyApp.Jido.__jido_storage__/0 by default
Jido.Agent.InstanceManager.child_spec(
  name: :sessions,
  agent: MyApp.SessionAgent,
  jido: MyApp.Jido,
  idle_timeout: :timer.minutes(15)
)

# Disable persistence for this manager
Jido.Agent.InstanceManager.child_spec(
  name: :ephemeral_sessions,
  agent: MyApp.SessionAgent,
  storage: nil
)
```

### Lifecycle Flow

1. **Get/Start**: `InstanceManager.get/3` looks up by key in Registry
2. **Thaw**: If not running but storage exists, agent is restored via `thaw`
3. **Fresh**: If no stored checkpoint, starts a fresh agent
4. **Attach**: Callers track interest via `AgentServer.attach/1`
5. **Idle**: When all attachments detach, idle timer starts
6. **Hibernate**: On timeout, agent is persisted via `hibernate`, then process stops

Manager-backed checkpoints are keyed by `{manager_name, pool_key}` to prevent
cross-manager collisions when multiple managers share one storage backend.

```elixir
# Get or start an agent (thaws if hibernated)
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")

# Track this caller's interest
:ok = Jido.AgentServer.attach(pid)

# When done, detach (starts idle timer if no other attachments)
:ok = Jido.AgentServer.detach(pid)
```

### Durable Dynamic Cron Registrations

When an agent registers a recurring job at runtime with `Directive.cron/3`,
`InstanceManager` persists that dynamic schedule as part of the checkpoint state.
Jido stages those specs under a reserved internal key, `:__cron_specs__`, and
re-registers them on thaw.

This durability scope is intentionally narrow:

- Dynamic `Directive.cron/3` registrations are persisted when storage is enabled
- Declarative `schedules:` entries are recreated from code on start
- Plugin schedules are recreated from code on start
- Missed cron ticks are not replayed during hibernate or downtime
- `storage: nil` keeps dynamic cron registrations runtime-only

### Example: Session Agent with Auto-Hibernate

```elixir
defmodule MyApp.SessionAgent do
  use Jido.Agent,
    name: "session_agent",
    schema: [
      user_id: [type: :string, required: true],
      cart: [type: {:list, :map}, default: []]
    ]

  @impl true
  def checkpoint(agent, _ctx) do
    thread = agent.state[:__thread__]
    {:ok, %{
      version: 1,
      agent_module: __MODULE__,
      id: agent.id,
      state: Map.drop(agent.state, [:__thread__]),
      thread: thread && %{id: thread.id, rev: thread.rev}
    }}
  end

  @impl true
  def restore(data, _ctx) do
    {:ok, agent} = new(id: data.id)
    {:ok, %{agent | state: Map.merge(agent.state, data.state)}}
  end
end
```

Usage with InstanceManager:

```elixir
# Start session (or resume if hibernated)
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123",
  initial_state: %{user_id: "user-123"}
)

# Process requests - state persists on idle
Jido.AgentServer.call(pid, Signal.new!("cart.add", %{item: "widget"}))

# After app restart, agent resumes from last checkpoint
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")
```

## When NOT to Persist

Skip persistence when:

- **Agents are stateless** — they fetch state from external sources on start
- **State is cheap to rebuild** — re-running init is faster than I/O
- **Short-lived workers** — task duration < hibernate overhead
- **Sensitive data** — secrets shouldn't hit disk/cache
- **High-churn agents** — frequent start/stop makes persistence overhead costly

```elixir
# Fire-and-forget task agents (no storage config)
Jido.Agent.InstanceManager.child_spec(
  name: :tasks,
  agent: MyApp.TaskAgent,
  idle_timeout: :timer.seconds(30)
  # No storage: - agent dies on idle, no restore
)
```

## Summary

| Question | Answer |
|----------|--------|
| **Configuration?** | `use Jido, otp_app: :my_app, storage: {Adapter, opts}` |
| **Manual API?** | `MyApp.Jido.hibernate(agent)` / `thaw(MyAgent, key)` |
| **Automatic API?** | `InstanceManager.get(:pool, key)` with `idle_timeout` |
| **Default?** | `Jido.Storage.ETS` (ephemeral) |
| **Production?** | `Jido.Storage.Redis` is one built-in durable option; custom adapters (for example Ecto/Ash) remain valid |
| **Key invariant?** | Never persist full thread in checkpoint; use pointer |

## Related

- [Agents](agents.md) — Agent module documentation
- [Runtime](runtime.md) — AgentServer and process-based execution
- [Configuration](configuration.md) — Jido instance configuration
- [Worker Pools](worker-pools.md) — Pre-warmed agent pools for throughput
