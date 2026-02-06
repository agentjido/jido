# Jido.Plugin System Overview

`Jido.Plugin` is a compile-time macro system that packages **actions, state, configuration, routing, scheduling, and lifecycle hooks** into composable units that attach to Jido Agents. Plugins participate at every phase: Agent compile-time, `Agent.new/1`, `AgentServer.init/1`, and runtime signal processing.

---

## Table of Contents

- [1. Architecture](#1-architecture)
- [2. Compile-Time Configuration Options](#2-compile-time-configuration-options)
- [3. Capabilities](#3-capabilities)
- [4. Overridable Callbacks](#4-overridable-callbacks)
- [5. Generated Accessor Functions](#5-generated-accessor-functions)
- [6. Manifest vs Spec](#6-manifest-vs-spec)
- [7. Config Resolution (3-Layer Merge)](#7-config-resolution-3-layer-merge)
- [8. Route Expansion and Conflict Detection](#8-route-expansion-and-conflict-detection)
- [9. Schedule Expansion and Signal Generation](#9-schedule-expansion-and-signal-generation)
- [10. Requirements Validation](#10-requirements-validation)
- [11. Multi-Instance Support (`as:`)](#11-multi-instance-support-as)
- [12. Discovery and Introspection](#12-discovery-and-introspection)
- [13. Lifecycle Integration](#13-lifecycle-integration)

---

## 1. Architecture

### Core Modules

| Module | Purpose |
|---|---|
| `Jido.Plugin` | Behaviour + `__using__` macro. Defines callbacks, generates accessors, validates config at compile time. |
| `Jido.Plugin.Spec` | Runtime struct representing a plugin attached to a specific agent (includes per-agent `config`). |
| `Jido.Plugin.Manifest` | Compile-time struct with full metadata: capabilities, requirements, routes, schedules, etc. |
| `Jido.Plugin.Instance` | Normalized mount unit. Handles `as:` aliasing, config resolution, and derived `state_key`/`route_prefix`. |
| `Jido.Plugin.Config` | 3-layer config resolution: schema defaults → app env → per-agent overrides. |
| `Jido.Plugin.Routes` | Expands route declarations with instance prefixes; detects conflicts with priority-based resolution. |
| `Jido.Plugin.Schedules` | Expands cron schedule declarations; generates signal types and job IDs. |
| `Jido.Plugin.Requirements` | Validates `{:config, key}`, `{:app, name}`, and `{:plugin, name}` requirements at compile time. |

### Minimal Example

```elixir
defmodule MyApp.ChatPlugin do
  use Jido.Plugin,
    name: "chat",
    state_key: :chat,
    actions: [MyApp.Actions.SendMessage, MyApp.Actions.ListHistory],
    schema: Zoi.object(%{
      messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
      model: Zoi.string() |> Zoi.default("gpt-4")
    }),
    routes: [
      {"send", MyApp.Actions.SendMessage},
      {"history", MyApp.Actions.ListHistory}
    ]

  @impl Jido.Plugin
  def mount(_agent, config) do
    {:ok, %{initialized_at: DateTime.utc_now()}}
  end
end

defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    plugins: [
      MyApp.ChatPlugin,
      {MyApp.DatabasePlugin, %{pool_size: 5}}
    ]
end
```

---

## 2. Compile-Time Configuration Options

These are the options accepted by `use Jido.Plugin, ...`, validated at compile time via `Zoi.parse` against the plugin config schema.

| Option | Type | Required | Default | Purpose |
|---|---|---|---|---|
| `name` | `String.t()` | **yes** | — | Plugin identity. Validated by `Jido.Util.validate_name/1` (letters, numbers, underscores). Used as base for `route_prefix`. |
| `state_key` | `atom()` | **yes** | — | Key under which plugin state is nested in the agent's state map. |
| `actions` | `[module()]` | **yes** | — | Action modules the plugin provides. Validated by `Jido.Util.validate_actions/1`. Aggregated into the agent's action set. |
| `description` | `String.t()` | no | `nil` | Human-readable description. Appears in Manifest and Discovery metadata. |
| `category` | `String.t()` | no | `nil` | Organizational category. Appears in Manifest and Discovery metadata. |
| `vsn` | `String.t()` | no | `nil` | Version string. |
| `otp_app` | `atom()` | no | `nil` | Enables app-env config resolution via `Application.get_env(otp_app, PluginModule)`. |
| `schema` | `Zoi.schema()` | no | `nil` | Zoi schema for the plugin's state slice. Defaults are seeded into agent state during `new/1`. |
| `config_schema` | `Zoi.schema()` | no | `nil` | Zoi schema for per-agent configuration validation. |
| `signal_patterns` | `[String.t()]` | no | `[]` | Legacy signal patterns. Used for cross-product route generation when `routes` is empty and no custom `router/1` exists. |
| `tags` | `[String.t()]` | no | `[]` | Tag strings for Discovery filtering. |
| `capabilities` | `[atom()]` | no | `[]` | Capability atoms. Contributed to the agent's capability union. |
| `requires` | `[tuple()]` | no | `[]` | Dependency declarations: `{:config, key}`, `{:app, name}`, `{:plugin, name}`. Validated at agent compile time. |
| `routes` | `[tuple()]` | no | `[]` | Signal route declarations: `{path, ActionModule}` or `{path, ActionModule, opts}`. |
| `schedules` | `[tuple()]` | no | `[]` | Cron schedule declarations: `{cron_expr, ActionModule}` or `{cron_expr, ActionModule, opts}`. |

### Route Tuple Options

Routes support these options in the third element:

- `priority: integer` — Default is `-10`. Higher values win over lower in conflict resolution.
- `on_conflict: :replace` — Silently override conflicting routes instead of raising a compile error.

### Schedule Tuple Options

Schedules support these options in the third element:

- `tz: "America/New_York"` — Timezone for cron evaluation. Default is `"Etc/UTC"`.
- `signal: "custom.signal"` — Custom signal type. Default auto-generates `"{route_prefix}.__schedule__.{action_name}"`.

---

## 3. Capabilities

### 3.1 Plugin-Scoped State Management

Each plugin owns a state slice keyed under `state_key` in the agent's state map. If a `schema` is provided, Zoi defaults are seeded automatically during `Agent.new/1`. The `mount/2` callback can then augment that initial state.

```
agent.state = %{
  chat: %{messages: [], model: "gpt-4", initialized_at: ~U[...]},
  database: %{pool_size: 5}
}
```

### 3.2 Action Packaging

Plugins bundle action modules. At agent compile time, all plugin actions are aggregated into the agent's unified action set (`MyAgent.actions/0`), deduplicated.

### 3.3 Signal Routing

Plugins contribute routes to the agent's signal router through three mechanisms (in precedence order):

1. **Declarative routes** (`routes:` option) — expanded with instance prefix at compile time.
2. **Custom `router/1` callback** — returns routes dynamically at runtime.
3. **Legacy `signal_patterns` × `actions` cross-product** — fallback when neither routes nor custom router are defined.

### 3.4 Pre-Routing Signal Hook

The `handle_signal/2` callback runs before routing for every incoming signal. It can:
- **Continue** — `{:ok, :continue}` or `{:ok, nil}` → proceed to normal routing.
- **Override** — `{:ok, {:override, ActionModule}}` → bypass router, execute this action instead.
- **Abort** — `{:error, reason}` → reject the signal with an error.

Hooks execute in plugin declaration order; the first override or error short-circuits the chain.

### 3.5 Result Transformation (Call Path Only)

The `transform_result/3` callback decorates the agent struct returned from `AgentServer.call/3`. It does **not** affect internal server state or `cast/2` results. All plugin transforms chain in declaration order.

### 3.6 Supervised Child Processes

The `child_spec/1` callback lets plugins start worker processes during `AgentServer.init/1`. Children are monitored and tracked in the server's `children` map under tag `{:plugin, plugin_module, id}`.

### 3.7 Sensor Subscriptions

The `subscriptions/2` callback returns `{SensorModule, config}` tuples. Each spawns a `Jido.Sensor.Runtime` process that emits signals into the agent. Sensors are monitored under tag `{:sensor, plugin_module, sensor_module}`.

### 3.8 Cron Scheduling

The `schedules:` option registers cron jobs via `Jido.Scheduler.run_every/3` during AgentServer post-init. Each tick casts a generated signal into the agent, processed through the normal routing pipeline.

### 3.9 Dependency Validation

The `requires:` option enforces compile-time checks: required config keys must be non-nil, OTP applications must be available, and dependent plugins must be mounted.

### 3.10 Discovery and Introspection

Plugins generate `__plugin_metadata__/0` and `manifest/0` functions for runtime discovery via `Jido.Discovery` (listing, filtering, slug-based lookup).

### 3.11 Multi-Instance Support

A single plugin module can be mounted multiple times with different configurations using the `as:` option. Each instance gets derived `state_key` and `route_prefix` values to isolate state and routing.

---

## 4. Overridable Callbacks

All six callbacks have default implementations and are marked `defoverridable`:

### `mount/2`

```elixir
@callback mount(agent :: term(), config :: map()) :: {:ok, map() | nil} | {:error, term()}
```

**Default:** `{:ok, %{}}` (no additional state)

**When called:** During `Agent.new/1`, after schema defaults are seeded.

**Override to:** Initialize derived state, seed data from config, perform conditional setup based on previously-mounted plugin state (the `agent` argument contains state from earlier plugins).

**Return values:**
- `{:ok, map()}` — merged into the plugin's state slice via `Map.merge/2`.
- `{:ok, nil}` — schema defaults only.
- `{:error, reason}` — raises during agent creation.

---

### `router/1`

```elixir
@callback router(config :: map()) :: term()
```

**Default:** `nil` (no custom routes)

**When called:** At AgentServer runtime when building the signal router; also checked at compile time to decide whether legacy route expansion should be skipped.

**Override to:** Provide dynamic routes that depend on resolved config. Returns a list of `{signal_type, ActionModule}` tuples.

**Side effect:** If `router/1` returns a non-empty list, compile-time route expansion from `signal_patterns` is suppressed to avoid double-routing.

---

### `handle_signal/2`

```elixir
@callback handle_signal(signal :: term(), context :: map()) ::
            {:ok, term()} | {:ok, {:override, term()}} | {:error, term()}
```

**Default:** `{:ok, nil}` (continue to normal routing)

**When called:** Before signal routing in AgentServer, for every incoming signal.

**Context map keys:** `:agent`, `:agent_module`, `:plugin`, `:plugin_spec`, `:config`.

**Override to:** Implement gatekeeping, auditing, signal rewriting, or hard action overrides.

**Return values:**
- `{:ok, nil}` or `{:ok, :continue}` — proceed to next plugin hook, then router.
- `{:ok, {:override, action_spec}}` — bypass router, execute this action.
- `{:error, reason}` — abort signal processing; AgentServer wraps into `Jido.Error.execution_error`.

---

### `transform_result/3`

```elixir
@callback transform_result(action :: module() | String.t(), result :: term(), context :: map()) ::
            term()
```

**Default:** identity (returns `result` unchanged)

**When called:** After signal processing, on the synchronous `call` path only. Does not affect `cast/2` or internal server state.

**Context map keys:** `:agent`, `:agent_module`, `:plugin`, `:plugin_spec`, `:config`.

**Override to:** Decorate the returned agent struct with metadata, timestamps, computed fields, etc.

---

### `child_spec/1`

```elixir
@callback child_spec(config :: map()) :: nil | Supervisor.child_spec() | [Supervisor.child_spec()]
```

**Default:** `nil` (no child processes)

**When called:** During `AgentServer.handle_continue(:post_init, ...)`.

**Override to:** Start supervised worker processes (GenServers, Agents, Tasks) tied to the agent's lifecycle. Children are monitored; crashes produce exit signals in the AgentServer.

**Return values:**
- `nil` — no children.
- `%{id: ..., start: {m, f, a}}` — single child.
- `[%{...}, ...]` — multiple children.

---

### `subscriptions/2`

```elixir
@callback subscriptions(config :: map(), context :: map()) :: [{module(), keyword() | map()}]
```

**Default:** `[]` (no subscriptions)

**When called:** During `AgentServer.handle_continue(:post_init, ...)`.

**Context map keys:** `:agent_id`, `:agent_module`, `:agent_ref`, `:plugin_spec`, `:jido_instance`.

**Override to:** Attach sensor processes that emit signals into this agent instance. Each `{SensorModule, sensor_config}` tuple spawns a `Jido.Sensor.Runtime`.

---

## 5. Generated Accessor Functions

`use Jido.Plugin` generates these accessor functions, all marked `defoverridable`:

### Core Accessors (from required options)

| Function | Spec | Source |
|---|---|---|
| `name/0` | `String.t()` | `@validated_opts.name` |
| `state_key/0` | `atom()` | `@validated_opts.state_key` |
| `actions/0` | `[module()]` | `@validated_opts.actions` |

### Optional Accessors

| Function | Spec | Source |
|---|---|---|
| `description/0` | `String.t() \| nil` | `@validated_opts[:description]` |
| `category/0` | `String.t() \| nil` | `@validated_opts[:category]` |
| `vsn/0` | `String.t() \| nil` | `@validated_opts[:vsn]` |
| `otp_app/0` | `atom() \| nil` | `@validated_opts[:otp_app]` |
| `schema/0` | `Zoi.schema() \| nil` | `@validated_opts[:schema]` |
| `config_schema/0` | `Zoi.schema() \| nil` | `@validated_opts[:config_schema]` |

### List Accessors

| Function | Spec | Default |
|---|---|---|
| `signal_patterns/0` | `[String.t()]` | `[]` |
| `tags/0` | `[String.t()]` | `[]` |
| `capabilities/0` | `[atom()]` | `[]` |
| `requires/0` | `[tuple()]` | `[]` |
| `routes/0` | `[tuple()]` | `[]` |
| `schedules/0` | `[tuple()]` | `[]` |

### Introspection Functions (generated but NOT `defoverridable`)

| Function | Returns |
|---|---|
| `plugin_spec/1` | `%Jido.Plugin.Spec{}` with per-agent config merged in |
| `manifest/0` | `%Jido.Plugin.Manifest{}` with all compile-time metadata |
| `__plugin_metadata__/0` | `%{name, description, category, tags}` for `Jido.Discovery` |

---

## 6. Manifest vs Spec

| | `Jido.Plugin.Manifest` | `Jido.Plugin.Spec` |
|---|---|---|
| **Purpose** | Compile-time metadata for discovery and tooling | Runtime representation of a plugin attached to an agent |
| **Scope** | What the plugin *provides* | What the plugin *is configured as* for a specific agent |
| **Includes** | `capabilities`, `requires`, `routes`, `schedules`, `otp_app`, `subscriptions` | `config`, `signal_patterns`, `tags`, `actions` |
| **Generated by** | `manifest/0` | `plugin_spec/1` |
| **Used by** | `Instance.new/1` (base keys), `Requirements` (validation), Agent (capabilities union) | Agent `@plugin_specs`, AgentServer signal hooks |

---

## 7. Config Resolution (3-Layer Merge)

`Jido.Plugin.Config.resolve_config/2` merges configuration from three sources:

```
Priority: Schema defaults (lowest) → App env → Per-agent overrides (highest)
```

1. **Schema defaults** — Applied by `Zoi.parse/2` during validation. Fill missing keys.
2. **Application environment** — `Application.get_env(otp_app, PluginModule, %{})`. Requires `otp_app:` option.
3. **Per-agent overrides** — From the agent's `plugins:` declaration: `{MyPlugin, %{key: value}}`.

Merge happens as `Map.merge(app_env_config, per_agent_overrides)`, then the merged map is validated against `config_schema` (if present), which applies Zoi defaults for any remaining missing keys.

```elixir
# config/config.exs
config :my_app, MyApp.SlackPlugin,
  token: "default-token",
  channel: "#general"

# Agent declaration
use Jido.Agent,
  plugins: [{MyApp.SlackPlugin, %{channel: "#support"}}]

# Resolved: %{token: "default-token", channel: "#support"}
```

---

## 8. Route Expansion and Conflict Detection

### Route Expansion

`Jido.Plugin.Routes.expand_routes/1` prefixes every route path with the instance's `route_prefix`:

```
Plugin route: {"send", SendAction}
Instance prefix: "chat"
Expanded: {"chat.send", SendAction, []}

Multi-instance prefix: "support.chat"
Expanded: {"support.chat.send", SendAction, []}
```

**Expansion logic (precedence):**

1. If `manifest.routes` is non-empty → expand those with prefix.
2. Else if `router/1` returns a non-empty list → return `[]` (routes come from runtime router).
3. Else → generate legacy cross-product: `signal_patterns × actions`.

### Conflict Detection

`Routes.detect_conflicts/1` validates all expanded routes at agent compile time:

- **Same path, same priority, no `on_conflict`** → compile error listing conflicting targets.
- **Same path, different priority** → higher priority wins silently.
- **Same path with `on_conflict: :replace`** → replaces without error (highest priority among `:replace` routes wins).

### Priority Layering

The AgentServer signal router assigns default priorities:

| Source | Default Priority |
|---|---|
| Strategy routes | `50` |
| Agent routes | `0` |
| Plugin routes | `-10` |
| Schedule-generated routes | `-20` |

Higher priority wins. Explicit agent routes override plugin routes by default.

---

## 9. Schedule Expansion and Signal Generation

### Expanded Schedule Spec

```elixir
%{
  cron_expression: "*/5 * * * *",
  action: MyApp.Actions.RefreshToken,
  job_id: {:plugin_schedule, :slack, MyApp.Actions.RefreshToken},
  signal_type: "slack.__schedule__.refresh_token",
  timezone: "Etc/UTC"
}
```

### Signal Type Generation

**Default pattern:** `"{route_prefix}.__schedule__.{action_name}"`

- `action_name` is derived from the module's last segment, underscored: `MyApp.Actions.RefreshToken` → `"refresh_token"`.
- Custom signal types override this: `{"*/5 * * * *", Action, signal: "custom.ping"}` → `"{prefix}.custom.ping"`.

### Integration

Schedule-generated signal types need routes to be dispatched. `Schedules.schedule_routes/1` creates routes at priority `-20`, included in compile-time conflict detection. At runtime, `Jido.Scheduler.run_every/3` registers cron jobs that cast signals into the AgentServer through the normal routing pipeline.

---

## 10. Requirements Validation

Plugins declare dependencies via the `requires:` option. Validated at agent compile time — failures raise `CompileError`.

### Requirement Types

| Form | Satisfied When |
|---|---|
| `{:config, key}` | `Map.get(resolved_config, key) != nil` |
| `{:app, app_name}` | `Application.spec(app_name) != nil` |
| `{:plugin, plugin_name}` | Another mounted plugin has this name (string comparison) |

### Example

```elixir
use Jido.Plugin,
  name: "slack",
  state_key: :slack,
  actions: [SlackAction],
  requires: [
    {:config, :token},
    {:app, :req},
    {:plugin, "http"}
  ]
```

If requirements are unmet, the agent raises at compile time:

```
** (CompileError) Missing requirements for plugins: slack requires {:config, :token}, {:app, :req}
```

---

## 11. Multi-Instance Support (`as:`)

A plugin can be mounted multiple times with different configs by using the `as:` option in keyword-list form:

```elixir
use Jido.Agent,
  plugins: [
    {MyApp.SlackPlugin, as: :support, token: "support-token"},
    {MyApp.SlackPlugin, as: :sales, token: "sales-token"}
  ]
```

### Derived Namespaces

| | No alias | `as: :support` |
|---|---|---|
| `state_key` | `:slack` | `:slack_support` |
| `route_prefix` | `"slack"` | `"support.slack"` |

State, routes, schedules, and config are fully isolated per instance.

### Declaration Formats

| Format | `as:` Support |
|---|---|
| `PluginModule` | No (nil alias) |
| `{PluginModule, %{key: value}}` | No (map form, nil alias) |
| `{PluginModule, [as: :alias, key: value]}` | Yes (keyword form) |

### Agent Accessors for Multi-Instance

- `MyAgent.plugin_config(PluginModule)` — returns config for the default instance (`as == nil`), or falls back to the first instance.
- `MyAgent.plugin_config({PluginModule, :support})` — returns config for the specific instance.
- `MyAgent.plugin_state(agent, PluginModule)` / `MyAgent.plugin_state(agent, {PluginModule, :support})` — analogous for state.

---

## 12. Discovery and Introspection

### Plugin Metadata Hook

`use Jido.Plugin` generates `__plugin_metadata__/0` returning:

```elixir
%{name: "chat", description: "...", category: "messaging", tags: ["ai", "chat"]}
```

### Jido.Discovery Integration

`Jido.Discovery` scans loaded applications for modules exporting `__plugin_metadata__/0` and indexes them:

- `Discovery.list_plugins/1` — list and filter plugins.
- `Discovery.get_plugin_by_slug/1` — lookup by stable 8-character hash derived from the module name.

### Manifest for Tooling

`manifest/0` returns a `%Jido.Plugin.Manifest{}` with the full compile-time picture: capabilities, requirements, routes, schedules, actions, schemas. Useful for ecosystem tooling, documentation generation, and dependency analysis.

---

## 13. Lifecycle Integration

### Phase 1: Agent Compile Time (`use Jido.Agent`)

1. Normalize plugin declarations into `%Instance{}` structs (config resolution happens here).
2. Build `@plugin_specs` from instances.
3. Validate state_key uniqueness and schema collisions.
4. Merge plugin schemas into agent schema.
5. Aggregate plugin actions into agent actions.
6. Expand and validate routes (including schedule-generated routes) with conflict detection.
7. Validate all plugin requirements.

### Phase 2: Agent Creation (`Agent.new/1`)

1. Seed plugin state defaults from Zoi schemas into agent state.
2. Call each plugin's `mount/2` callback (pure); merge returned state into plugin's state slice.

### Phase 3: AgentServer Initialization (`handle_continue(:post_init, ...)`)

1. Build runtime signal router (includes plugin routes + custom router routes).
2. Start plugin child processes (`child_spec/1`).
3. Start plugin sensor subscriptions (`subscriptions/2`).
4. Register plugin cron schedules.

### Phase 4: Signal Processing (runtime)

1. Run `handle_signal/2` hook chain (all plugins, in order).
2. Route signal to action via unified router.
3. Execute `agent_module.cmd/2`.
4. Process directives.
5. On `call` path only: apply `transform_result/3` chain (all plugins, in order).

---

## Complete Overridable Reference

Everything marked `defoverridable` in a single table:

| Function | Arity | Category | Default |
|---|---|---|---|
| `mount` | 2 | Callback | `{:ok, %{}}` |
| `router` | 1 | Callback | `nil` |
| `handle_signal` | 2 | Callback | `{:ok, nil}` |
| `transform_result` | 3 | Callback | identity (returns `result`) |
| `child_spec` | 1 | Callback | `nil` |
| `subscriptions` | 2 | Callback | `[]` |
| `name` | 0 | Accessor | from `@validated_opts.name` |
| `state_key` | 0 | Accessor | from `@validated_opts.state_key` |
| `actions` | 0 | Accessor | from `@validated_opts.actions` |
| `description` | 0 | Accessor | from `@validated_opts[:description]` |
| `category` | 0 | Accessor | from `@validated_opts[:category]` |
| `vsn` | 0 | Accessor | from `@validated_opts[:vsn]` |
| `otp_app` | 0 | Accessor | from `@validated_opts[:otp_app]` |
| `schema` | 0 | Accessor | from `@validated_opts[:schema]` |
| `config_schema` | 0 | Accessor | from `@validated_opts[:config_schema]` |
| `signal_patterns` | 0 | Accessor | from `@validated_opts[:signal_patterns]` or `[]` |
| `tags` | 0 | Accessor | from `@validated_opts[:tags]` or `[]` |
| `capabilities` | 0 | Accessor | from `@validated_opts[:capabilities]` or `[]` |
| `requires` | 0 | Accessor | from `@validated_opts[:requires]` or `[]` |
| `routes` | 0 | Accessor | from `@validated_opts[:routes]` or `[]` |
| `schedules` | 0 | Accessor | from `@validated_opts[:schedules]` or `[]` |
