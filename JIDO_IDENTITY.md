# Jido Identity Design

## Overview

Identity is a first-class agent primitive — a mostly-stable self-model stored under the reserved key `__identity__` in `agent.state`. It answers two questions:

1. **What can this agent do?** — Capabilities for orchestration and routing
2. **What lifecycle facts matter?** — Age, creation context, evolution state

Identity is intentionally not world knowledge (`__memory__`), not event history (`__thread__`), and not decision logic (`__strategy__`). It's the agent's machine-readable resume.

## Why Identity Deserves a Reserved Key

Capabilities need a predictable, framework-level access pattern. An orchestrator routing work to agents shouldn't have to know memory space conventions or parse strategy state. A reserved key makes capability queries trivial and uniform.

| Reserved Key | Question | Nature |
|---|---|---|
| `__strategy__` | How should I act? | Execution control |
| `__thread__` | What happened? | Append-only event log |
| `__memory__` | What do I know/want? | Mutable world model + tasks |
| `__identity__` | What am I / what can I do? | Mostly-stable self-model |
| `__parent__` | Who spawned me? | Hierarchy (set once) |

## Core Concept: Two Sections + Extensions

Identity has two core sections plus a plugin-owned extension surface. Agents already have `agent.name` and `agent.description` on the struct — Identity does not duplicate those.

### `profile` — Lifecycle Facts

Small, factual data about the agent's lifecycle state. The primary use case is `age` as the showcase for the evolve mechanic.

```elixir
profile: %{
  age: 3,
  generation: 2,
  origin: :spawned
}
```

| Key | Type | Purpose |
|---|---|---|
| `age` | integer | Years of simulated existence (evolve target) |
| `generation` | integer | Spawn generation (optional) |
| `origin` | atom | How the agent was created — `:configured`, `:spawned`, `:cloned` (optional) |

Keep this small. If a fact is about the world, it belongs in `__memory__.world`. If it's about what happened, it belongs in `__thread__`. Profile holds only facts about *the agent itself*.

### `capabilities` — Routing Manifest

A machine-readable manifest designed for orchestrators to route work. This is the primary reason Identity exists as a reserved key.

```elixir
capabilities: %{
  actions: [
    "MyApp.Actions.FetchURL",
    "MyApp.Actions.ParseHTML",
    "MyApp.Actions.ExtractLinks"
  ],
  tags: [:web, :fetch, :parsing],
  io: %{network?: true, filesystem?: false},
  limits: %{max_concurrency: 4, max_runtime_ms: 30_000}
}
```

| Key | Type | Purpose |
|---|---|---|
| `actions` | list of strings | Supported Action identifiers — the primary routing surface |
| `tags` | list of atoms | Coarse categorization for matchmaking (optional) |
| `io` | map | Operational I/O flags — what the agent needs access to (optional) |
| `limits` | map | Operational constraints — timeout, concurrency, etc. (optional) |

`actions` is the core. Everything else is optional metadata that makes routing smarter.

### `extensions` — Plugin-Owned Identity Data

A namespaced map where plugins hang additional identity data. Core doesn't interpret this — it just stores it. Each plugin owns a slice keyed by its plugin name.

```elixir
extensions: %{
  "character" => %{
    persona: %{
      traits: [%{name: "analytical", intensity: 0.9}],
      values: ["accuracy", "clarity"]
    },
    voice: %{tone: :professional, style: "Concise and precise."},
    __public__: %{
      persona: %{role: "Data analyst"},
      voice: %{tone: :professional}
    }
  },
  "safety" => %{
    guidelines: ["Never provide medical advice"],
    redlines: ["Never disclose API keys"],
    __public__: %{}
  }
}
```

The rules:

1. **Namespaced by plugin name** — no collisions, no coordination required
2. **Plugin-owned validation** — each plugin validates its own slice with its own Zoi schema
3. **Core is ignorant** — `Jido.Identity` never parses extension contents
4. **`__public__` convention** — plugins include a `__public__` key with data safe to share in snapshots

## Core Data Structure

```elixir
defmodule Jido.Identity do
  @schema Zoi.struct(
    __MODULE__,
    %{
      rev: Zoi.integer(description: "Monotonic revision, increments on mutation") |> Zoi.default(0),

      profile: Zoi.map(description: "Lifecycle facts about the agent") |> Zoi.default(%{
        age: nil
      }),

      capabilities: Zoi.map(description: "Routing manifest for orchestration") |> Zoi.default(%{
        actions: [],
        tags: [],
        io: %{},
        limits: %{}
      }),

      extensions: Zoi.map(description: "Plugin-owned identity extensions") |> Zoi.default(%{}),

      created_at: Zoi.integer(description: "Creation timestamp (ms)"),
      updated_at: Zoi.integer(description: "Last update timestamp (ms)")
    },
    coerce: true
  )
end
```

## Helper Module

Follows the exact pattern established by `Jido.Thread.Agent` and `Jido.Memory.Agent`:

```elixir
defmodule Jido.Identity.Agent do
  @key :__identity__

  # Container-level operations
  def key(), do: @key
  def get(agent, default \\ nil)
  def put(agent, identity)
  def update(agent, fun)
  def ensure(agent, opts \\ [])
  def has_identity?(agent)

  # Profile convenience
  def age(agent)
  def get_profile(agent, key, default \\ nil)
  def put_profile(agent, key, value)

  # Capability queries
  def capabilities(agent)
  def supports_action?(agent, action_id)
  def has_tag?(agent, tag)
  def actions(agent)
  def tags(agent)

  # Capability mutations
  def add_action(agent, action_id)
  def remove_action(agent, action_id)
  def add_tag(agent, tag)
  def set_limit(agent, key, value)
  def set_io(agent, key, value)

  # Extension operations (plugin-owned slices)
  def get_extension(agent, plugin_name, default \\ nil)
  def put_extension(agent, plugin_name, ext_map)
  def update_extension(agent, plugin_name, fun)
  def merge_extension(agent, plugin_name, patch)

  # Snapshot for sharing with other agents
  def snapshot(agent)
end
```

Usage:

```elixir
agent
|> Identity.Agent.ensure(profile: %{age: 0}, capabilities: %{
     actions: ["MyApp.Actions.FetchURL", "MyApp.Actions.ParseHTML"],
     tags: [:web, :parsing]
   })
|> Identity.Agent.add_action("MyApp.Actions.ExtractLinks")
|> Identity.Agent.set_limit(:max_runtime_ms, 30_000)
```

## Extensibility: How Plugins Layer onto Identity

Plugins extend identity through `extensions` — they never add keys to `profile` or `capabilities` for new semantics. Instead they layer richer meaning *alongside* core in their own namespace.

### Plugin Mount

When a plugin mounts, it initializes its identity extension slice:

```elixir
defmodule MyApp.CharacterPlugin do
  use Jido.Plugin,
    name: "character",
    state_key: :character,
    actions: [SetPersona, SetVoice, Evolve]

  @impl Jido.Plugin
  def mount(agent, config) do
    agent = Jido.Identity.Agent.ensure(agent)
    agent = Jido.Identity.Agent.put_extension(agent, "character", %{
      persona: config[:persona] || %{},
      voice: config[:voice] || %{},
      __public__: build_public(config)
    })
    {:ok, %{mounted_at: System.system_time(:millisecond)}}
  end

  defp build_public(config) do
    %{
      persona: Map.take(config[:persona] || %{}, [:role]),
      voice: Map.take(config[:voice] || %{}, [:tone])
    }
  end
end
```

### Plugin-Owned Accessors

Plugins provide their own higher-level API — core doesn't need to understand persona or voice:

```elixir
defmodule MyApp.Character do
  def persona(agent) do
    case Jido.Identity.Agent.get_extension(agent, "character") do
      nil -> nil
      ext -> ext[:persona]
    end
  end

  def voice(agent) do
    case Jido.Identity.Agent.get_extension(agent, "character") do
      nil -> nil
      ext -> ext[:voice]
    end
  end

  def set_persona(agent, persona) do
    Jido.Identity.Agent.update_extension(agent, "character", fn ext ->
      ext
      |> Map.put(:persona, persona)
      |> Map.update(:__public__, %{}, &Map.put(&1, :persona, Map.take(persona, [:role])))
    end)
  end
end
```

### Plugin-Owned Evolution

Core `evolve/2` handles `profile.age`. Plugins that need their own evolution semantics (trait drift, personality changes) provide a plugin-level action that composes with core evolve:

```elixir
defmodule MyApp.Character.Actions.Evolve do
  use Jido.Action,
    name: "character_evolve",
    schema: [days: [type: :integer, default: 0], years: [type: :integer, default: 0]]

  def run(params, ctx) do
    identity = ctx.state[:__identity__]

    # 1. Core evolution (age)
    identity = Jido.Identity.evolve(identity, Map.to_list(params))

    # 2. Plugin-specific evolution (trait drift, etc.)
    identity = update_in(identity, [:extensions, "character"], fn ext ->
      evolve_persona(ext, params)
    end)

    {:ok, %{__identity__: identity}}
  end

  defp evolve_persona(ext, _params) do
    # Plugin-owned logic: drift trait intensities, update voice, etc.
    ext
  end
end
```

This keeps core evolve deterministic and testable while giving plugins full control over their own evolution semantics.

### What Plugins Should NOT Do

- **Don't add keys to `profile`** — profile is for core lifecycle facts only
- **Don't add keys to `capabilities`** — use existing `actions`/`tags`/`io`/`limits` fields via core helpers
- **Don't store world knowledge in extensions** — that belongs in `__memory__.world`
- **Don't store event history in extensions** — that belongs in `__thread__`

Extensions are for *self-model descriptors* — things that describe what the agent *is*, not what it *knows* or what *happened*.

## Orchestrator Query Model

### Local (agent struct available)

When the orchestrator has direct access to the agent struct:

```elixir
Identity.Agent.capabilities(agent)
Identity.Agent.supports_action?(agent, "MyApp.Actions.FetchURL")
Identity.Agent.has_tag?(agent, :web)
```

An orchestrator routing work across a pool of agents:

```elixir
agents
|> Enum.filter(&Identity.Agent.supports_action?(&1, required_action))
|> Enum.filter(&Identity.Agent.has_tag?(&1, :web))
|> Enum.sort_by(&Identity.Agent.age/1, :desc)  # prefer experienced agents
|> List.first()
```

### Remote (agent process only)

Standardize a request/response signal pair:

```elixir
# Request
%Jido.Signal{type: "jido.identity.capabilities.request", data: %{}}

# Response
%Jido.Signal{
  type: "jido.identity.capabilities.response",
  data: %{
    name: agent.name,
    capabilities: %{actions: [...], tags: [...], io: %{...}, limits: %{...}},
    profile: %{age: 3},
    extensions: %{"character" => %{persona: %{role: "Data analyst"}, voice: %{tone: :professional}}}
  }
}
```

The response includes a **public snapshot** — core data plus public projections from extensions.

### Snapshot

```elixir
def snapshot(agent) do
  identity = get(agent)
  %{
    capabilities: identity.capabilities,
    profile: Map.take(identity.profile, [:age, :generation, :origin]),
    extensions: public_extensions(identity.extensions)
  }
end

defp public_extensions(extensions) do
  extensions
  |> Enum.filter(fn {_name, ext} -> Map.has_key?(ext, :__public__) end)
  |> Enum.map(fn {name, ext} -> {name, ext[:__public__]} end)
  |> Map.new()
end
```

Agents share snapshots, not full identities. The `__public__` convention lets each plugin control exactly what gets exposed.

## Evolution

Identity evolves via explicit state transforms. Age is the primary showcase — a simple, testable demonstration that agent state can change over simulated time.

### Pure Function

```elixir
defmodule Jido.Identity do
  def evolve(identity, opts \\ []) do
    years = opts[:years] || 0
    days = opts[:days] || 0
    total_years = years + div(days, 365)

    identity
    |> update_in([:profile, :age], &((&1 || 0) + total_years))
    |> Map.update!(:rev, &(&1 + 1))
    |> Map.put(:updated_at, System.system_time(:millisecond))
  end
end
```

### As an Action

```elixir
defmodule Jido.Identity.Actions.Evolve do
  use Jido.Action,
    name: "identity_evolve",
    description: "Evolve agent identity over simulated time",
    schema: [
      days: [type: :integer, default: 0],
      years: [type: :integer, default: 0]
    ]

  def run(params, ctx) do
    identity = ctx.state[:__identity__]
    evolved = Jido.Identity.evolve(identity, Map.to_list(params))
    {:ok, %{__identity__: evolved}}
  end
end
```

Strategies can trigger evolution:
- On a schedule (via `Directive.Schedule` or `Directive.Cron`)
- After N interactions (counted in strategy state)
- On explicit command

### What Evolves (v1 vs. Future)

| Target | v1 | Future |
|---|---|---|
| `profile.age` | Increments by elapsed time | Yes |
| `capabilities` | Static | Could grow/shrink as agent learns/forgets actions |
| `extensions` | Plugin-managed | Plugins provide their own evolve actions |
| `profile.generation` | Static | Could increment on clone/fork |

## Multi-Agent: Self vs. Others

`__identity__` is the agent's own self-model. Models of *other* agents belong in `__memory__`:

```elixir
# Own identity (reserved key)
agent.state[:__identity__]
# => %Jido.Identity{profile: %{age: 3}, capabilities: %{actions: [...]}}

# Model of another agent (memory world key)
agent.state[:__memory__].spaces.world.data[:known_agents]["bob_id"]
# => %{
#   snapshot: %{capabilities: %{actions: [...], tags: [:analysis]}},
#   trust: 0.8,
#   last_seen: ~U[2026-02-01 10:00:00Z]
# }
```

## Implementation Plan

### Phase 1 — Core Structs + Helpers (S effort)

1. `Jido.Identity` struct with `profile`, `capabilities`, and `extensions`
2. `Jido.Identity.Agent` helper module (container ops, profile ops, capability queries/mutations, extension ops)
3. `Jido.Identity.snapshot/1` with `__public__` projection
4. Unit tests

### Phase 2 — Evolution (S effort)

1. `Jido.Identity.evolve/2` pure function
2. `Jido.Identity.Actions.Evolve` action module
3. Tests for deterministic evolution

### Phase 3 — Orchestrator Integration (M effort)

1. Signal-based capability query protocol
2. AgentServer handler for capability requests
3. Integration tests with multi-agent routing

## Risks and Guardrails

1. **Capability drift** — Identity claims actions that aren't actually loaded. Consider an optional validation hook in `ensure/2` that checks declared actions exist (dev/test only, not enforced in production).

2. **Reserved key sprawl** — `__identity__` should be the last reserved key. If a new concept doesn't warrant cross-cutting framework support, it's a `__memory__` world key or plugin state.

3. **Extension bloat** — Extensions are for self-model descriptors, not data stores. Large artifacts (knowledge bases, conversation logs, embeddings) belong in `__memory__` or external providers. Keep extension slices small.

4. **Capabilities vs. Plugins** — Plugins register actions dynamically. Capabilities should reflect the *current* set of available actions, not a static declaration. Consider auto-syncing capabilities when plugins mount/unmount.

5. **Extension schema drift** — Plugins should include an optional `vsn` key in their extension slice and handle migration in their own actions if the schema evolves.
