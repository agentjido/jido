# Persistence & Storage

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

## Choosing Your Persistence Model

| Approach | When to Use | API |
|----------|-------------|-----|
| **Manual** | Explicit control over when to persist | `MyApp.Jido.hibernate/1`, `thaw/2` |
| **Automatic** | Idle-based lifecycle for per-user/entity agents | `InstanceManager.get/3` with `idle_timeout` |
| **None** | Stateless agents, cheap rebuilds, short-lived tasks | Skip storage config |

Both manual and automatic approaches use the same underlying `Jido.Storage` behaviour.

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

### Lifecycle Flow

1. **Get/Start**: `InstanceManager.get/3` looks up by key in Registry
2. **Thaw**: If not running but storage exists, agent is restored via `thaw`
3. **Fresh**: If no stored checkpoint, starts a fresh agent
4. **Attach**: Callers track interest via `AgentServer.attach/1`
5. **Idle**: When all attachments detach, idle timer starts
6. **Hibernate**: On timeout, agent is persisted via `hibernate`, then process stops

```elixir
# Get or start an agent (thaws if hibernated)
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")

# Track this caller's interest
:ok = Jido.AgentServer.attach(pid)

# When done, detach (starts idle timer if no other attachments)
:ok = Jido.AgentServer.detach(pid)
```

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

## Migration from Legacy API

If migrating from the older `Jido.Agent.Persistence` / `Jido.Agent.Store` API:

| Old API | New API |
|---------|---------|
| `Jido.Agent.Persistence.hibernate/4` | `MyApp.Jido.hibernate/1` or `Jido.Persist.hibernate/2` |
| `Jido.Agent.Persistence.thaw/3` | `MyApp.Jido.thaw/2` or `Jido.Persist.thaw/3` |
| `Jido.Agent.Store` behaviour (3 callbacks) | `Jido.Storage` behaviour (6 callbacks) |
| `dump/2` callback | `checkpoint/2` callback |
| `load/2` callback | `restore/2` callback |

Key differences:

1. **Unified storage** — One adapter handles both checkpoints and threads
2. **Thread-aware** — Automatically flushes journal before checkpoint
3. **Thread pointer** — Checkpoint stores pointer, not full thread
4. **Configured on Jido instance** — Not per-call configuration

## Summary

| Question | Answer |
|----------|--------|
| **Configuration?** | `use Jido, otp_app: :my_app, storage: {Adapter, opts}` |
| **Manual API?** | `MyApp.Jido.hibernate(agent)` / `thaw(MyAgent, key)` |
| **Automatic API?** | `InstanceManager.get(:pool, key)` with `idle_timeout` |
| **Default?** | `Jido.Storage.ETS` (ephemeral) |
| **Production?** | Implement `Jido.Storage` behaviour with Ecto/Ash |
| **Key invariant?** | Never persist full thread in checkpoint; use pointer |

## Related

- [Agents](agents.md) — Agent module documentation
- [Runtime](runtime.md) — AgentServer and process-based execution
- [Configuration](configuration.md) — Jido instance configuration
- [Worker Pools](worker-pools.md) — Pre-warmed agent pools for throughput
