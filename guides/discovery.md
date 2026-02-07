# Discovery & Introspection

**After:** You can list agents/actions and build tooling around Jido.

```elixir
# Find all actions in the :utility category
Jido.Discovery.list_actions(category: :utility)
# => [%{module: MyApp.FormatAction, name: "format", slug: "abc123de", ...}, ...]

# Lookup a specific sensor by slug
Jido.Discovery.get_sensor_by_slug("x7y8z9ab")
# => %{module: MyApp.TickSensor, name: "tick_sensor", ...}

# Build tooling: generate docs from all discovered agents
for agent <- Jido.Discovery.list_agents() do
  IO.puts("## #{agent.name}\n\n#{agent.description}")
end
```

## How Discovery Works

Discovery scans all loaded applications for modules that export metadata functions (`__action_metadata__/0`, `__sensor_metadata__/0`, etc.). Results are cached in `:persistent_term` for fast, concurrent reads.

Components are indexed automatically when you call `use Jido.Action`, `use Jido.Sensor`, `use Jido.Agent`, or `use Jido.Plugin`.

## Initialization

Initialize the catalog during application startup:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... other children
    ]

    # Initialize discovery catalog asynchronously (non-blocking)
    Jido.Discovery.init_async()

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

The catalog builds in the background. Queries before completion return empty lists.

## Listing Components

Each component type has a dedicated list function:

```elixir
# List all actions
Jido.Discovery.list_actions()

# List all sensors
Jido.Discovery.list_sensors()

# List all agents
Jido.Discovery.list_agents()

# List all plugins
Jido.Discovery.list_plugins()

# List all demos
Jido.Discovery.list_demos()
```

### Filtering Options

All list functions accept the same filter options:

| Option | Type | Match | Description |
|--------|------|-------|-------------|
| `:name` | string | partial | Filter by component name |
| `:description` | string | partial | Filter by description |
| `:category` | atom | exact | Filter by category |
| `:tag` | atom | exact | Component must have this tag |
| `:limit` | integer | — | Maximum results |
| `:offset` | integer | — | Skip first N results |

Filters use AND logic—all specified filters must match.

```elixir
# Actions in the :utility category
Jido.Discovery.list_actions(category: :utility)

# Sensors tagged with :monitoring, max 5 results
Jido.Discovery.list_sensors(tag: :monitoring, limit: 5)

# Agents with "worker" in the name
Jido.Discovery.list_agents(name: "worker")

# Paginated results
Jido.Discovery.list_actions(limit: 10, offset: 20)
```

## Component Metadata

Each discovered component returns a metadata map:

```elixir
%{
  module: MyApp.CoolAction,
  name: "cool_action",
  description: "Does cool stuff",
  slug: "abc123de",
  category: :utility,
  tags: [:cool, :stuff]
}
```

| Field | Description |
|-------|-------------|
| `module` | The Elixir module |
| `name` | Human-readable name |
| `description` | What the component does |
| `slug` | Unique 8-character identifier (derived from module hash) |
| `category` | Component category (atom or nil) |
| `tags` | List of tags for filtering |

## Lookup by Slug

Find a specific component by its unique slug:

```elixir
Jido.Discovery.get_action_by_slug("abc123de")
# => %{module: MyApp.CoolAction, ...} or nil

Jido.Discovery.get_sensor_by_slug("x7y8z9ab")
Jido.Discovery.get_agent_by_slug("def456gh")
Jido.Discovery.get_plugin_by_slug("ijk789lm")
Jido.Discovery.get_demo_by_slug("nop012qr")
```

Slugs are stable—derived from the module name hash—so they survive restarts.

## Catalog Management

### Refresh the Catalog

Rescan all applications for new components:

```elixir
:ok = Jido.Discovery.refresh()
```

Use this after hot code reloading or dynamically loading modules.

### Check Last Update

```elixir
{:ok, %DateTime{} = timestamp} = Jido.Discovery.last_updated()
```

### Get Full Catalog

```elixir
{:ok, catalog} = Jido.Discovery.catalog()
# catalog.components.actions  => [%{...}, ...]
# catalog.components.sensors  => [%{...}, ...]
# catalog.last_updated        => %DateTime{}
```

## Building Admin/Debug Tooling

### List All Signal Routes

Combine discovery with agent route introspection:

```elixir
defmodule MyApp.Debug do
  def list_all_routes do
    for agent <- Jido.Discovery.list_agents() do
      routes = 
        if function_exported?(agent.module, :signal_routes, 0) do
          agent.module.signal_routes()
        else
          []
        end

      {agent.module, routes}
    end
  end
end

MyApp.Debug.list_all_routes()
# => [
#   {MyApp.CounterAgent, [{"counter.increment", IncrementAction}]},
#   {MyApp.WorkerAgent, [{"worker.*", HandleWorkAction}]}
# ]
```

### Generate API Documentation

```elixir
defmodule MyApp.DocGenerator do
  def generate_action_docs do
    Jido.Discovery.list_actions()
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&format_action/1)
    |> Enum.join("\n\n")
  end

  defp format_action(action) do
    """
    ### #{action.name}

    **Module:** `#{inspect(action.module)}`
    **Category:** #{action.category || "—"}
    **Tags:** #{format_tags(action.tags)}

    #{action.description}
    """
  end

  defp format_tags(nil), do: "—"
  defp format_tags([]), do: "—"
  defp format_tags(tags), do: Enum.map_join(tags, ", ", &"`#{&1}`")
end

# Generate markdown documentation
docs = MyApp.DocGenerator.generate_action_docs()
File.write!("docs/actions.md", docs)
```

### Component Dashboard

Build a LiveView dashboard showing all registered components:

```elixir
defmodule MyAppWeb.DiscoveryLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, 
      actions: Jido.Discovery.list_actions(),
      sensors: Jido.Discovery.list_sensors(),
      agents: Jido.Discovery.list_agents(),
      plugins: Jido.Discovery.list_plugins()
    )}
  end

  def render(assigns) do
    ~H"""
    <h2>Actions (<%= length(@actions) %>)</h2>
    <ul>
      <%= for action <- @actions do %>
        <li><strong><%= action.name %></strong> — <%= action.description %></li>
      <% end %>
    </ul>
    
    <h2>Agents (<%= length(@agents) %>)</h2>
    <ul>
      <%= for agent <- @agents do %>
        <li><strong><%= agent.name %></strong> — <%= agent.description %></li>
      <% end %>
    </ul>
    """
  end
end
```

### Capability Checks

Query component metadata to determine system capabilities:

```elixir
defmodule MyApp.Capabilities do
  def has_ai_actions? do
    Jido.Discovery.list_actions(tag: :ai) |> Enum.any?()
  end

  def available_categories do
    Jido.Discovery.list_actions()
    |> Enum.map(& &1.category)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end

MyApp.Capabilities.has_ai_actions?()
# => true

MyApp.Capabilities.available_categories()
# => [:ai, :data, :utility]
```

## Performance

Discovery uses `:persistent_term` for storage:

- **Reads are O(1)** — direct memory access, no GenServer bottleneck
- **Concurrent reads** — all processes can read simultaneously
- **Writes are expensive** — avoid frequent `refresh/0` calls

For most applications, initialize once at startup and refresh only when deploying new code.

## Next Steps

- [Actions Guide](actions.md) — Implement actions that appear in discovery
- [Sensors Guide](your-first-sensor.md) — Create sensors that get indexed
- [Plugins Guide](plugins.md) — Package capabilities as discoverable plugins
