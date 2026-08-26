# State Operations

<!-- covers: jido.signals_and_directives.state_ops_internal_mutation -->

**After:** You can perform non-trivial state changes safely and consistently.

State operations are internal state transitions handled by the strategy layer during `cmd/2`. Unlike directives, they never reach the runtime.

```elixir
alias Jido.Agent.StateOp

{:ok, result, [
  %StateOp.SetState{attrs: %{status: :processing}},
  %StateOp.SetPath{path: [:metrics, :count], value: 42}
]}
```

## State Ops vs Directives

Jido separates two distinct concerns in action returns:

| Concept | Module | Purpose | Where Applied |
|---------|--------|---------|---------------|
| **State Operations** | `Jido.Agent.StateOp` | Internal state transitions | Strategy layer (during `cmd/2`) |
| **Directives** | `Jido.Agent.Directive` | External effects (emit, spawn, schedule) | Runtime (AgentServer) |

**Key principle:** State ops modify the agent before `cmd/2` returns. Directives pass through unchanged to the runtime.

```elixir
def run(params, context) do
  {:ok, %{result: "done"}, [
    %StateOp.SetState{attrs: %{step: :completed}},   # Applied by strategy
    %Directive.Emit{signal: my_signal}                # Passed to runtime
  ]}
end
```

## Available Operations

| StateOp | Purpose | Use When |
|---------|---------|----------|
| `SetState` | Deep merge attributes into state | Adding/updating fields while preserving others |
| `ReplaceState` | Replace state wholesale | Full reset, blob replacement |
| `DeleteKeys` | Remove top-level keys | Clearing ephemeral/temporary data |
| `SetPath` | Set value at nested path | Targeted nested updates |
| `DeletePath` | Delete value at nested path | Removing specific nested keys |

## SetState — Deep Merge

Merges attributes into state using `DeepMerge.deep_merge/2` semantics. Nested maps are merged recursively.

```elixir
defmodule UpdateMetadataAction do
  use Jido.Action,
    name: "update_metadata",
    schema: [version: [type: :string, required: true]]

  def run(%{version: version}, _context) do
    {:ok, %{}, %StateOp.SetState{attrs: %{metadata: %{version: version}}}}
  end
end
```

**Before state:**
```elixir
%{counter: 10, metadata: %{author: "alice"}}
```

**After action with `%{version: "2.0"}`:**
```elixir
%{counter: 10, metadata: %{author: "alice", version: "2.0"}}
```

Use the helper constructor for cleaner code:

```elixir
StateOp.set_state(%{status: :running, last_seen: DateTime.utc_now()})
```

## ReplaceState — Full Replacement

Replaces state completely — no merge, no preserved keys.

```elixir
defmodule ResetAction do
  use Jido.Action,
    name: "reset",
    schema: []

  def run(_params, _context) do
    {:ok, %{}, %StateOp.ReplaceState{state: %{status: :idle, counter: 0}}}
  end
end
```

**When to use:**
- Full state reset
- Replacing large blob structures
- Ensuring no stale keys remain

```elixir
StateOp.replace_state(%{fresh: true, initialized_at: DateTime.utc_now()})
```

## DeleteKeys — Remove Top-Level Fields

Removes specified top-level keys. Safe to call with non-existent keys.

```elixir
defmodule ClearCacheAction do
  use Jido.Action,
    name: "clear_cache",
    schema: []

  def run(_params, _context) do
    {:ok, %{}, %StateOp.DeleteKeys{keys: [:temp, :cache, :pending_request]}}
  end
end
```

**Before:**
```elixir
%{counter: 5, temp: "data", cache: %{items: []}}
```

**After:**
```elixir
%{counter: 5}
```

```elixir
StateOp.delete_keys([:temp, :cache])
```

## SetPath / DeletePath — Nested Updates

For targeted updates at arbitrary nesting depths.

### SetPath

Sets a value at a nested path. Creates intermediate maps if they don't exist.

```elixir
defmodule UpdateConfigAction do
  use Jido.Action,
    name: "update_config",
    schema: [timeout: [type: :integer, required: true]]

  def run(%{timeout: timeout}, _context) do
    {:ok, %{}, %StateOp.SetPath{path: [:config, :database, :timeout], value: timeout}}
  end
end
```

**Before:**
```elixir
%{config: %{}}
```

**After with `timeout: 5000`:**
```elixir
%{config: %{database: %{timeout: 5000}}}
```

### DeletePath

Removes a value at a nested path. Handles non-existent paths gracefully.

```elixir
defmodule RemoveSecretAction do
  use Jido.Action,
    name: "remove_secret",
    schema: []

  def run(_params, _context) do
    {:ok, %{}, %StateOp.DeletePath{path: [:config, :credentials, :api_key]}}
  end
end
```

```elixir
StateOp.set_path([:metrics, :requests, :total], 1000)
StateOp.delete_path([:temp, :cache, :stale_entry])
```

## Cookbook

### Append to a List

Lists aren't deeply merged — you need to read the current value and build the new list.

```elixir
defmodule AppendMessageAction do
  use Jido.Action,
    name: "append_message",
    schema: [message: [type: :string, required: true]]

  def run(%{message: message}, context) do
    current_messages = get_in(context.state, [:messages]) || []
    new_messages = current_messages ++ [message]
    
    {:ok, %{}, %StateOp.SetPath{path: [:messages], value: new_messages}}
  end
end
```

### Update Nested Counter

Increment a deeply nested value:

```elixir
defmodule IncrementRequestCountAction do
  use Jido.Action,
    name: "increment_request_count",
    schema: [amount: [type: :integer, default: 1]]

  def run(%{amount: amount}, context) do
    current = get_in(context.state, [:metrics, :requests, :count]) || 0
    
    {:ok, %{}, %StateOp.SetPath{path: [:metrics, :requests, :count], value: current + amount}}
  end
end
```

### Conditional Updates

Return different state ops based on conditions:

```elixir
defmodule ProcessItemAction do
  use Jido.Action,
    name: "process_item",
    schema: [item: [type: :map, required: true]]

  def run(%{item: item}, context) do
    pending = Map.get(context.state, :pending_items, [])
    
    if item.priority == :high do
      {:ok, %{processed: item.id}, [
        %StateOp.SetState{attrs: %{last_high_priority: DateTime.utc_now()}},
        %StateOp.SetPath{path: [:pending_items], value: pending -- [item]}
      ]}
    else
      {:ok, %{queued: item.id}, %StateOp.SetPath{path: [:pending_items], value: pending ++ [item]}}
    end
  end
end
```

### Combining Multiple State Ops

Actions can return a list of state ops:

```elixir
defmodule CompleteTaskAction do
  use Jido.Action,
    name: "complete_task",
    schema: []

  def run(_params, _context) do
    {:ok, %{completed_at: DateTime.utc_now()}, [
      %StateOp.SetState{attrs: %{status: :completed}},
      %StateOp.DeleteKeys{keys: [:temp, :in_progress_data]},
      %StateOp.SetPath{path: [:metrics, :completed_count], value: 1}
    ]}
  end
end
```

## Common Gotchas

### Missing Intermediate Paths with DeletePath

`DeletePath` uses `pop_in/2` — if intermediate keys don't exist, the operation is a no-op.

```elixir
# State: %{config: %{}}
# This does nothing (no error, but also no change):
%StateOp.DeletePath{path: [:config, :nested, :missing]}
```

### SetPath Overwrites Non-Map Intermediates

If a path element exists but isn't a map, `SetPath` creates a new map, overwriting the existing value.

```elixir
# State: %{config: "not a map"}
%StateOp.SetPath{path: [:config, :timeout], value: 5000}
# Result: %{config: %{timeout: 5000}}  — string is gone
```

### List Handling in SetState

`SetState` uses deep merge, which merges maps recursively. Lists are **replaced**, not concatenated.

```elixir
# State: %{items: [1, 2, 3]}
%StateOp.SetState{attrs: %{items: [4, 5]}}
# Result: %{items: [4, 5]}  — not [1, 2, 3, 4, 5]
```

Use `SetPath` with explicit list manipulation to append:

```elixir
current = context.state[:items] || []
%StateOp.SetPath{path: [:items], value: current ++ [4, 5]}
```

### Schema Validation Timing

State ops are applied by the strategy layer. If your agent uses schema validation, validation happens **after** state ops are applied. Invalid state ops can fail validation.

```elixir
# If your schema expects :status to be an atom:
%StateOp.SetState{attrs: %{status: "invalid_string"}}
# May cause validation errors downstream
```

### Order of Operations

State ops are applied in order. Later ops can overwrite earlier ones:

```elixir
[
  %StateOp.SetState{attrs: %{counter: 1}},
  %StateOp.SetState{attrs: %{counter: 2}},
  %StateOp.SetState{attrs: %{counter: 3}}
]
# Final state: counter: 3
```

---

See `Jido.Agent.StateOp` moduledoc for the complete API reference.
