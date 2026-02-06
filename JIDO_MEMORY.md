# Jido Memory Design

## Overview

Memory is a first-class agent primitive — a mutable, revisable cognitive substrate stored under the reserved key `__memory__` in `agent.state`. It complements Thread (append-only episodic log) and Strategy (execution control) as the third pillar of agent cognition.

Memory answers **"what does the agent currently believe/want?"** while Thread answers **"what happened?"** and Strategy answers **"how should the agent act?"**

## Motivation

Jido agents at the core are not LLM-specific. "Memory" in classical AI is a proxy for world state — beliefs, goals, percepts, working data. For LLM agents, memory maps to context window management, RAG retrieval, and conversation summarization. A single abstraction must serve both.

### Why Not Just `agent.state`?

Agent state is a flat map owned by the user's schema. Memory is a structured cognitive container with:

- An open set of named **spaces** with two built-in defaults (`tasks` and `world`)
- Revision tracking at both container and per-space level for concurrency control
- A clear boundary between "application state" and "cognitive state"
- Extensibility — add custom spaces for domain-specific cognitive structures

### Why Not Just Thread?

| | Thread | Memory |
|---|---|---|
| **Mutability** | Append-only | Mutable (overwrite, delete, update) |
| **Purpose** | Canonical record of what happened | Current world model |
| **Analogy** | Episodic memory / audit log | Working memory + task list |
| **Retention** | Everything, forever | Can forget, summarize, compact |

Thread is a ledger. Memory is a whiteboard.

## Reserved Key Landscape

| Key | Concept | Mutability | Module |
|---|---|---|---|
| `__strategy__` | How the agent thinks | Mutable (by strategy) | `Jido.Agent.Strategy.State` |
| `__thread__` | What happened | Append-only | `Jido.Thread.Agent` |
| `__parent__` | Who spawned me | Set once | `Jido.AgentServer.State` |
| **`__memory__`** | What the agent knows/wants | Mutable, revisable | `Jido.Memory.Agent` (proposed) |

The reserved key namespace should stay tight. Additional cognitive concepts (attention, plans, percepts) can live as **keys within `world`** or as **custom named spaces** within memory — but never as new reserved keys in `agent.state`.

## Core Concept: Spaces

Memory is an **open map of named spaces**. Every agent starts with two built-in defaults — `tasks` and `world` — but you can add any number of custom spaces. Each space follows the same `Jido.Memory.Space` contract (data, rev, metadata), giving you a uniform interface regardless of how many spaces exist.

The space's type is determined by its `data` — a `%{}` map or a `[]` list. No explicit kind tag is needed; idiomatic Elixir pattern matching and guards (`is_map/1`, `is_list/1`) handle dispatch.

### Built-in Defaults

| Space | Data type | Purpose | Guaranteed |
|---|---|---|---|
| `tasks` | list | Ordered list of TODOs — the agent's agenda | Yes (created by `ensure/2`) |
| `world` | map | Current world model — everything the agent knows right now | Yes (created by `ensure/2`) |

The rule: **raw events go to Thread, derived understanding goes to `world`, next actions go to `tasks`.**

### Custom Spaces

Add spaces for any domain-specific cognitive structure. Custom spaces use the same `Space` contract — just pass a map or list as the initial data.

```elixir
agent
|> Memory.Agent.ensure_space(:blackboard, %{})
|> Memory.Agent.ensure_space(:evidence, [])
|> Memory.Agent.ensure_space(:relationships, %{})
```

**Naming conventions for plugin-owned spaces:**
- Use atom namespacing to avoid collisions: `:"rag:cache"`, `:"planner:steps"`
- Built-in names (`:tasks`, `:world`) are reserved and cannot be deleted

When to use a custom space vs. a key in `world`:
- **Use `world` keys** for simple data that doesn't need independent revision tracking or isolation
- **Use a custom space** when the data has its own lifecycle, needs independent revision tracking, or represents a distinct cognitive concern (e.g., a blackboard, evidence store, relationship graph)

### `tasks` — What to Do

An ordered list of items the agent intends to act on. Simple TODO semantics.

```elixir
%Space{data: [
  %{id: "t1", text: "Investigate room 4", status: :open},
  %{id: "t2", text: "Report findings to user", status: :open},
  %{id: "t3", text: "Check sensor calibration", status: :done}
]}
```

Task items are intentionally minimal. Position in the list determines priority — first item is highest priority.

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Unique identifier |
| `text` | string | yes | What to do |
| `status` | `:open \| :done` | yes | Current state |

### `world` — What the Agent Knows

A map holding the agent's current world model. Everything that used to be "beliefs", "working memory", "percepts", "tool state" — it's all keys in `world`.

```elixir
%Space{data: %{
  temperature: 22,
  door_open: true,
  last_reading: %{sensor: 3, value: 22, at: 1706_000_000},
  conversation_summary: "User asked about room conditions...",
  pointers: %{semantic_index: "agent_123_vectors"}
}}
```

Recommended key conventions (not enforced):

| Key | Purpose |
|---|---|
| `:facts` | Durable beliefs about the world (map) |
| `:scratch` | Transient working data, caches, intermediate results (map) |
| `:tool_state` | State from recent tool/action calls (map) |
| `:summary` | Compressed conversation or episode summary (string/map) |
| `:pointers` | References to external stores — vector indexes, files, etc. (map) |

These are just keys. Use whatever keys make sense for your agent.

## Core Data Structures

### `Jido.Memory.Space` — The Unit of Memory

Every space — built-in or custom — is a `Space` struct with a uniform contract. The type of `data` determines how the space behaves — pattern matching and guards do the rest:

```elixir
defmodule Jido.Memory.Space do
  @schema Zoi.struct(
    __MODULE__,
    %{
      data: Zoi.any(description: "Space contents — a map or list"),
      rev: Zoi.integer(description: "Per-space revision, increments on mutation") |> Zoi.default(0),
      metadata: Zoi.map(description: "Space-level metadata") |> Zoi.default(%{})
    },
    coerce: true
  )

  def map?(%__MODULE__{data: data}) when is_map(data), do: true
  def map?(_), do: false

  def list?(%__MODULE__{data: data}) when is_list(data), do: true
  def list?(_), do: false
end
```

Per-space `rev` enables fine-grained concurrency control — two independent updates to different spaces don't contend on the same revision counter.

### `Jido.Memory` — The Container

```elixir
defmodule Jido.Memory do
  @schema Zoi.struct(
    __MODULE__,
    %{
      id: Zoi.string(description: "Unique memory identifier"),
      rev: Zoi.integer(description: "Container-level monotonic revision") |> Zoi.default(0),
      spaces: Zoi.map(description: "Open map of named spaces") |> Zoi.default(%{
        tasks: %Jido.Memory.Space{data: []},
        world: %Jido.Memory.Space{data: %{}}
      }),
      created_at: Zoi.integer(description: "Creation timestamp (ms)"),
      updated_at: Zoi.integer(description: "Last update timestamp (ms)"),
      metadata: Zoi.map(description: "Arbitrary metadata") |> Zoi.default(%{})
    },
    coerce: true
  )
end
```

The container `rev` increments on any mutation. Each space's `rev` increments independently when that specific space is updated. Both are available for optimistic concurrency depending on the granularity needed.

## Architecture: Two Layers

### Layer 1 — Pure Helpers (`Jido.Memory.Agent`)

Mirrors `Jido.Thread.Agent` and `Jido.Agent.Strategy.State` patterns. Operates on the agent struct, returns updated agent. No side effects.

```elixir
defmodule Jido.Memory.Agent do
  @key :__memory__

  # Container-level operations
  def get(agent, default \\ nil)
  def put(agent, memory)
  def update(agent, fun)
  def ensure(agent, opts \\ [])
  def has_memory?(agent)

  # Generic space operations
  def space(agent, name)
  def space_put(agent, name, %Space{})
  def space_update(agent, name, fun)
  def space_delete(agent, name)              # raises on :tasks / :world
  def ensure_space(agent, name, default_data) # default_data: %{} or []
  def spaces(agent)                          # returns the full spaces map
  def has_space?(agent, name)

  # Map space operations — guarded with is_map(space.data)
  def get_in_space(agent, space_name, key, default \\ nil)
  def put_in_space(agent, space_name, key, value)
  def delete_from_space(agent, space_name, key)
  def update_space_data(agent, space_name, fun)

  # List space operations — guarded with is_list(space.data)
  def append_to_space(agent, space_name, item)
  def prepend_to_space(agent, space_name, item)
  def insert_in_space(agent, space_name, index, item)
  def remove_from_space(agent, space_name, item_id)
  def update_in_space(agent, space_name, item_id, fun)

  # World convenience wrappers (delegate to map ops with space: :world)
  def world_get(agent, key, default \\ nil)
  def world_put(agent, key, value)
  def world_delete(agent, key)
  def world_update(agent, fun)
  def world(agent)

  # Task convenience wrappers (delegate to list ops with space: :tasks)
  def tasks(agent)
  def tasks_add(agent, text, opts \\ [])
  def tasks_insert(agent, index, text, opts \\ [])
  def tasks_complete(agent, task_id)
  def tasks_remove(agent, task_id)
  def tasks_next(agent)
  def tasks_reorder(agent, task_ids)
  def tasks_open(agent)
end
```

The `world_*` and `tasks_*` functions are thin wrappers over the generic space APIs. Guards on `is_map/1` and `is_list/1` dispatch the right behavior — no explicit type tags needed.

Usage in an action:

```elixir
defmodule MyApp.Actions.ProcessObservation do
  use Jido.Action, name: "process_observation", schema: [...]

  def run(params, ctx) do
    state = ctx.state
    memory = state[:__memory__]

    {:ok, %{
      world: Map.put(memory.spaces.world.data, :temperature, params.temp),
      tasks: memory.spaces.tasks.data ++ [%{id: "t_new", text: "Verify reading", status: :open}]
    }}
  end
end
```

Or from a strategy:

```elixir
agent
|> Memory.Agent.world_put(:door_open, true)
|> Memory.Agent.world_put(:last_check, now)
|> Memory.Agent.tasks_add("Investigate room 4")
```

Using custom spaces:

```elixir
agent
|> Memory.Agent.ensure_space(:blackboard, %{})
|> Memory.Agent.put_in_space(:blackboard, :hypothesis, "door was left open by occupant")
|> Memory.Agent.put_in_space(:blackboard, :confidence, 0.7)

agent
|> Memory.Agent.ensure_space(:evidence, [])
|> Memory.Agent.append_to_space(:evidence, %{id: "e1", text: "Door sensor triggered at 3pm", source: :sensor})
```

### Layer 2 — Impure Backends (`Jido.Memory.Provider`)

For memory operations that require I/O (vector search, persistent storage). Follows the adapter pattern established by `Jido.Thread.Store` and `Jido.Storage`.

```elixir
defmodule Jido.Memory.Provider do
  @type adapter_state :: term()

  @callback init(opts :: keyword()) :: {:ok, adapter_state()} | {:error, term()}
  @callback get(adapter_state(), key :: term(), opts :: keyword()) ::
              {:ok, adapter_state(), term()} | {:error, adapter_state(), term()}
  @callback put(adapter_state(), key :: term(), value :: term(), opts :: keyword()) ::
              {:ok, adapter_state()} | {:error, adapter_state(), term()}
  @callback query(adapter_state(), query :: term(), opts :: keyword()) ::
              {:ok, adapter_state(), [term()]} | {:error, adapter_state(), term()}
  @callback delete(adapter_state(), key :: term(), opts :: keyword()) ::
              {:ok, adapter_state()} | {:error, adapter_state(), term()}

  @optional_callbacks [query: 3]
end
```

Planned providers:

| Provider | Backend | Use Case |
|---|---|---|
| `Jido.Memory.Provider.Inline` | In-struct maps | Default, pure, no I/O |
| `Jido.Memory.Provider.ETS` | ETS tables | Fast KV, ephemeral |
| `Jido.Memory.Provider.VectorStore` | pgvector / FAISS / etc. | Semantic search, RAG |

External backends are referenced via `world[:pointers]`, not by adding new spaces.

### Directive-Based Memory I/O

To preserve `cmd/2` purity, external memory operations use directives. This matches the existing `DirectiveExec` protocol:

```elixir
%Jido.Agent.Directive.Memory.Query{
  request_id: "req_...",
  query: %{text: "relevant context for task", top_k: 5},
  provider: :semantic,
  opts: [],
  reply_signal_type: "jido.memory.result"
}

%Jido.Agent.Directive.Memory.Upsert{
  request_id: "req_...",
  items: [%{key: "fact_1", value: "...", embedding: [...]}],
  provider: :semantic,
  opts: []
}

%Jido.Agent.Directive.Memory.Delete{
  request_id: "req_...",
  keys: [:stale_fact],
  provider: :semantic
}
```

Results return as signals:

```elixir
%Jido.Signal{
  type: "jido.memory.result",
  data: %{
    request_id: "req_...",
    status: :ok,
    result: [%{key: "fact_1", score: 0.92, value: "..."}],
    meta: %{provider: :pgvector, latency_ms: 12}
  }
}
```

Strategies route these signals back into actions for processing, completing the async loop.

## Plugin Integration

Memory is **core** (reserved key), but plugins **extend** it — by writing to existing spaces or by adding their own custom spaces:

```elixir
defmodule MyApp.RAGPlugin do
  use Jido.Plugin,
    name: "rag",
    state_key: :rag,
    actions: [Recall, Remember, Forget, Summarize],
    signal_patterns: ["jido.memory.result"]

  @impl Jido.Plugin
  def mount(agent, config) do
    agent = Jido.Memory.Agent.ensure(agent)
    agent = Jido.Memory.Agent.ensure_space(agent, :"rag:cache", %{})
    agent = Jido.Memory.Agent.world_put(agent, :pointers, %{
      semantic: %{provider: config[:provider] || Jido.Memory.Provider.ETS, index: config[:index]}
    })
    {:ok, %{mounted_at: System.system_time(:millisecond)}}
  end

  @impl Jido.Plugin
  def router(_config) do
    [
      {"jido.memory.result", MyApp.Actions.HandleMemoryResult}
    ]
  end
end
```

The relationship: **Memory is where cognitive state lives; plugins are how you add abilities/providers.** Plugins should namespace their custom spaces (e.g., `:"rag:cache"`) to avoid collisions with other plugins.

## Projection Pipeline: Thread → Memory

The most powerful composition is a **projector** that compiles Thread entries into Memory. This is how episodic memory becomes working knowledge.

```elixir
defmodule Jido.Memory.Projector do
  @callback project(memory :: Jido.Memory.t(), thread :: Jido.Thread.t(), ctx :: map()) ::
              {:ok, Jido.Memory.t()} | {:ok, Jido.Memory.t(), [directive()]}
end
```

Use cases:

- Summarize conversation history into `world[:summary]` (context compression)
- Extract entities from thread entries into `world[:facts]`
- Embed new messages into a vector store (via directives, referenced by `world[:pointers]`)
- Derive next actions and add to `tasks`

Projectors can run:
- On a strategy tick (periodic)
- After N thread entries accumulate (threshold-based)
- As an explicit action (on demand)

```elixir
defmodule MyApp.Projectors.ConversationSummarizer do
  @behaviour Jido.Memory.Projector

  @impl true
  def project(memory, thread, _ctx) do
    recent = Thread.slice(thread, max(0, thread.stats.entry_count - 50), thread.stats.entry_count)
    messages = Enum.filter(recent, &(&1.kind == :message))

    memory = Memory.world_put(memory, :summary, %{
      content: summarize(messages),
      source: :projector,
      projected_at: System.system_time(:millisecond),
      covers_seq: {List.first(recent).seq, List.last(recent).seq}
    })

    {:ok, memory}
  end
end
```

## Architecture Mappings

The extensible space model supports multiple agent architectures. Simple agents use just `world` + `tasks`. Complex agents add custom spaces for cleaner separation of cognitive concerns.

### BDI (Beliefs-Desires-Intentions)

Using custom spaces for clean BDI separation:

```elixir
spaces: %{
  world: %Space{data: %{
    facts: %{door: :open, temperature: 22}
  }},
  tasks: %Space{data: [
    %{id: "t1", text: "Navigate to exit 3", status: :open}
  ]},
  desires: %Space{data: %{
    goals: MapSet.new([:find_exit, :stay_warm])
  }},
  plans: %Space{data: %{
    navigate_to: [...plan steps...]
  }}
}
```

Or keep it simple with just `world` keys:

```elixir
world: %{
  facts: %{door: :open, temperature: 22},
  desires: MapSet.new([:find_exit, :stay_warm]),
  plan_library: %{navigate_to: [...plan steps...]}
}
```

### Blackboard

A natural fit for custom spaces — each knowledge source gets its own space:

```elixir
spaces: %{
  world: %Space{data: %{}},
  tasks: %Space{data: []},
  hypothesis: %Space{data: %{}},
  evidence: %Space{data: []},
  solution: %Space{data: %{}}
}
```

### LLM Agent (ReAct / Tool-Use)

```elixir
spaces: %{
  world: %Space{data: %{
    scratch: %{current_query: "...", step: 3},
    tool_state: %{available: [:search, :calculator], last_result: %{}},
    pointers: %{semantic: %{provider: :pgvector, index: "agent_123"}}
  }},
  tasks: %Space{data: [
    %{id: "t1", text: "Search for relevant docs", status: :done},
    %{id: "t2", text: "Synthesize answer", status: :open}
  ]}
}
```

## Other Agent Primitives Considered

| Concept | Decision | Rationale |
|---|---|---|
| Identity / Profile | **No reserved key** | Use `agent.name`, `agent.description`, and `world[:profile]` |
| Relationships / Social | **No reserved key** | `__parent__` + `__children__` (via AgentServer) already exist; peer relationships go in `world` or a custom `:relationships` space |
| Attention / Focus | **World key or space** | `world[:attention]` or a dedicated `:attention` space for complex attention models |
| Plan / Agenda | **Tasks** | The `tasks` space handles this; complex planners can add a `:plans` space |
| Capabilities | **Plugin manifest** | Already handled by plugin system |
| Communication / Mailbox | **Signals + AgentServer** | Already handled by signal routing |
| Environment Model | **World key** | `world[:facts]` |

The principle: **reserved keys are for framework-level concerns that every agent needs.** Domain-specific cognitive structures are keys within `world`, custom spaces, or plugin state. The choice between a `world` key and a custom space depends on whether the data needs independent revision tracking and lifecycle management.

## Implementation Plan

### Phase 1 — Core Structs + Helpers (S effort)

1. `Jido.Memory.Space` struct (data, rev, metadata) with guard-based type dispatch
2. `Jido.Memory` struct with default `tasks` + `world` spaces
3. `Jido.Memory.Agent` helper module (container ops, generic space ops, generic kv/list ops, world/tasks convenience wrappers)
4. Unit tests covering custom space creation, generic operations, and convenience wrappers

### Phase 2 — Provider Behaviour + Inline Provider (M effort)

1. `Jido.Memory.Provider` behaviour
2. `Jido.Memory.Provider.Inline` (default, operates on struct data)
3. `Jido.Memory.Provider.ETS` (fast KV backend)
4. Wire into AgentServer for directive execution

### Phase 3 — Directives + Signal Loop (M effort)

1. `Jido.Agent.Directive.Memory.{Query, Upsert, Delete}` structs
2. `DirectiveExec` protocol implementations
3. Standard `jido.memory.result` signal type
4. Integration tests with strategy round-trips

### Phase 4 — Projectors + Advanced Providers (L effort)

1. `Jido.Memory.Projector` behaviour
2. Example projector (Thread → world summarizer)
3. Vector store provider

## Risks and Guardrails

1. **Purity leaks** — Providers must only be accessible to AgentServer (directive interpreter), not to agent modules/actions directly. If convenience APIs are added later, they must produce directives, not I/O.

2. **Space/world bloat** — Keep spaces lean. Store summaries + refs, not raw blobs. Large artifacts belong in external stores referenced by `world[:pointers]`. Consider TTL or size limits on transient data. The ability to add custom spaces is not an invitation to create unbounded numbers of them.

3. **Confusing overlap with plugins** — Memory is where cognitive state lives; plugins are how you add abilities/providers.

4. **Premature key conventions** — The recommended world keys (`:facts`, `:scratch`, `:tool_state`, `:summary`, `:pointers`) are conventions, not enforcement. Let usage patterns emerge before standardizing.

5. **Space name collisions** — Plugins adding custom spaces should namespace them (e.g., `:"rag:cache"`, `:"planner:steps"`) to avoid collisions. The built-in names `:tasks` and `:world` are reserved and protected from deletion.

6. **Data type constraints** — The framework provides generic operations for maps (`is_map/1`) and lists (`is_list/1`). Other data types in `space.data` are allowed but the framework provides no generic operations for them — the owning plugin/module is responsible for its own manipulation logic.
