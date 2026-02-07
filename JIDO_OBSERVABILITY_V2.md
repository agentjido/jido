# Jido Observability V2 — Per-Instance Debugging & Telemetry

*Supersedes `JIDO_DEBUG_PLAN.md` and `JIDO_INSTANCE_OBSERVABILITY_PLAN.md`.*

## Problem

Jido's runtime model is **per-instance** — each `use Jido` module is an independent OTP supervisor tree with its own registry, agent supervisor, and task supervisor. But the observability stack is **global**:

- `Jido.Telemetry` — single GenServer, one handler set, one global config namespace
- `Jido.Telemetry.Config` — reads `config :jido, :telemetry`, uses `Application.compile_env` (runtime changes unreliable)
- `Jido.Observe` — reads `config :jido, :observability`, instance-blind facade
- `Jido.Observe.Log` — separate threshold from a separate config namespace
- `AgentServer` debug mode — per-agent opt-in, disconnected from everything above

Users face four config surfaces to "see what's happening":

```elixir
config :logger, level: :debug
config :jido, :telemetry, log_level: :debug, log_args: :keys_only
config :jido, :observability, log_level: :info, debug_events: :off
# + per-agent: AgentServer.start_link(debug: true)
```

Two separate `log_level` keys. No way to debug one instance without flooding another. No single entrypoint for "just show me everything."

## Design

### Core Invariants

1. **Every telemetry event carries `:jido_instance`** (or `nil` for non-instance contexts).
2. **All observability config resolves through `Jido.Observe.Config`** — one module, one resolution order.
3. **`Jido.Debug` is a runtime override provider** consumed by `Observe.Config`, not a separate patching layer.
4. **One global handler attachment**, instance-aware via metadata. No per-instance handler proliferation.
5. **Fully backward compatible.** Existing global config becomes the default fallback.

### Config Resolution Order

For any observability setting, `Observe.Config` resolves in this order:

```
1. Jido.Debug runtime override     (persistent_term, per-instance)
2. Per-instance app config          (config :my_app, MyApp.Jido, telemetry: [...])
3. Global app config                (config :jido, :telemetry / :observability)
4. Hardcoded default
```

When `instance` is `nil`, steps 1-2 are skipped.

### User Experience

**IEx — "just show me everything":**

```elixir
MyApp.Jido.debug(:on)       # developer-friendly verbosity for this instance
MyApp.Jido.debug(:verbose)  # maximum detail — trace-level, full args
MyApp.Jido.debug(:off)      # back to configured defaults
MyApp.Jido.debug()          # query current level => :off

# Per-agent (still works, unchanged)
MyApp.Jido.debug(pid, :on)

# Quick inspection
MyApp.Jido.recent(pid)
MyApp.Jido.recent(pid, 200)
```

**Scripts / Livebook:**

```elixir
{:ok, _} = Jido.start()
Jido.debug(:on)             # applies to Jido.Default
```

**Boot-time config (per-instance):**

```elixir
# config/dev.exs
config :my_app, MyApp.Jido,
  debug: true               # or :verbose
```

**Per-instance observability tuning (production):**

```elixir
# config/config.exs
config :my_app, MyApp.PublicJido,
  telemetry: [log_level: :info],
  observability: [debug_events: :off, redact_sensitive: true]

config :my_app, MyApp.InternalJido,
  telemetry: [log_level: :debug, log_args: :full],
  observability: [debug_events: :all, redact_sensitive: false, tracer: MyApp.OtelTracer]
```

Instances without per-instance config inherit from global `config :jido, :telemetry` / `config :jido, :observability`.

### Debug Levels

| Level | Telemetry log_level | Telemetry log_args | Observe debug_events | Observe log_level | AgentServer ring buffer | Redaction |
|-------|--------------------|--------------------|---------------------|-------------------|------------------------|-----------|
| `:off` | config value | config value | config value | config value | per-agent opt-in | config value |
| `:on` | `:debug` | `:keys_only` | `:minimal` | `:debug` | all agents in instance | **unchanged** |
| `:verbose` | `:trace` | `:full` | `:all` | `:debug` | all agents in instance | **unchanged** |

Redaction is never automatically disabled. Explicit opt-in only:

```elixir
MyApp.Jido.debug(:verbose, redact: false)
```

---

## New Modules

### `Jido.Observe.Config`

Single source of truth for all observability settings. Replaces the split between `Jido.Telemetry.Config` and `Jido.Observe`'s inline config reads.

```elixir
defmodule Jido.Observe.Config do
  @moduledoc """
  Resolves observability configuration with per-instance support.

  Resolution: Debug override → instance config → global config → default.
  """

  @type instance :: atom() | nil

  # --- Telemetry settings ---
  @spec telemetry_log_level(instance()) :: :trace | :debug | :info | :warning | :error
  @spec telemetry_log_args(instance()) :: :keys_only | :full | :none
  @spec slow_signal_threshold_ms(instance()) :: non_neg_integer()
  @spec slow_directive_threshold_ms(instance()) :: non_neg_integer()
  @spec interesting_signal_types(instance()) :: [String.t()]
  @spec trace_enabled?(instance()) :: boolean()

  # --- Observe settings ---
  @spec observe_log_level(instance()) :: Logger.level()
  @spec debug_events(instance()) :: :off | :minimal | :all
  @spec debug_events_enabled?(instance()) :: boolean()
  @spec redact_sensitive?(instance()) :: boolean()
  @spec tracer(instance()) :: module()

  # --- Debug buffer settings ---
  @spec debug_max_events(instance()) :: non_neg_integer()
end
```

Resolution pattern (same for every setting):

```elixir
@default_debug_max_events 500

def telemetry_log_level(instance \\ nil)
def telemetry_log_level(nil), do: global_telemetry(:log_level, @default_log_level)

def telemetry_log_level(instance) do
  with nil <- Jido.Debug.override(instance, :telemetry_log_level),
       nil <- instance_telemetry(instance, :log_level) do
    global_telemetry(:log_level, @default_log_level)
  end
end

def debug_max_events(instance \\ nil)
def debug_max_events(nil), do: global_telemetry(:debug_max_events, @default_debug_max_events)

def debug_max_events(instance) do
  with nil <- Jido.Debug.override(instance, :debug_max_events),
       nil <- instance_telemetry(instance, :debug_max_events) do
    global_telemetry(:debug_max_events, @default_debug_max_events)
  end
end

defp instance_telemetry(instance, key) do
  otp_app = instance_otp_app(instance)

  if otp_app do
    otp_app
    |> Application.get_env(instance, [])
    |> Keyword.get(:telemetry, [])
    |> Keyword.get(key)
  end
end

defp instance_otp_app(instance) do
  if is_atom(instance) and function_exported?(instance, :__otp_app__, 0) do
    instance.__otp_app__()
  end
end

defp global_telemetry(key, default) do
  :jido |> Application.get_env(:telemetry, []) |> Keyword.get(key, default)
end
```

**No `Observe.Config.Registry` module.** Per-instance config resolution uses `instance.__otp_app__/0` — a function generated by `use Jido` — instead of a persistent_term registry. This eliminates lifecycle/unregister complexity and test-cleanup concerns. For `Jido.Default` (not a `use Jido` module), `function_exported?/3` returns `false` and resolution falls through to global config.

### `Jido.Debug`

Per-instance runtime debug state. Consumed by `Observe.Config` as the highest-priority override.

```elixir
defmodule Jido.Debug do
  @moduledoc """
  Per-instance debug mode for Jido agents.

  Provides a single entrypoint to control observability verbosity
  at runtime, scoped to a specific Jido instance.
  """

  @type level :: :off | :on | :verbose
  @type instance :: atom()

  @spec enable(instance(), level(), keyword()) :: :ok
  def enable(instance, level \\ :on, opts \\ [])

  @spec disable(instance()) :: :ok
  def disable(instance)

  @spec level(instance()) :: level()
  def level(instance)

  @spec enabled?(instance()) :: boolean()
  def enabled?(instance)

  @spec override(instance(), atom()) :: term() | nil
  def override(instance, key)

  @spec maybe_enable_from_config(atom(), instance()) :: :ok
  def maybe_enable_from_config(otp_app, instance)

  @spec reset(instance()) :: :ok
  def reset(instance)
end
```

**Storage:** `:persistent_term` keyed by `{:jido_debug, instance}`.

```elixir
# When :on
:persistent_term.put({:jido_debug, MyApp.Jido}, %{
  level: :on,
  overrides: %{
    telemetry_log_level: :debug,
    telemetry_log_args: :keys_only,
    observe_log_level: :debug,
    observe_debug_events: :minimal
  }
})

# When :verbose
:persistent_term.put({:jido_debug, MyApp.Jido}, %{
  level: :verbose,
  overrides: %{
    telemetry_log_level: :trace,
    telemetry_log_args: :full,
    observe_log_level: :debug,
    observe_debug_events: :all
  }
})

# When :off — erase the key entirely (fast path)
:persistent_term.erase({:jido_debug, MyApp.Jido})
```

`override/2` reads from the overrides map:

```elixir
def override(instance, key) do
  case :persistent_term.get({:jido_debug, instance}, nil) do
    nil -> nil
    %{overrides: overrides} -> Map.get(overrides, key)
  end
end
```

Optional `redact: false` in opts writes an additional override:

```elixir
def enable(instance, level, opts) do
  overrides = build_overrides(level)
  overrides =
    if Keyword.get(opts, :redact) == false do
      Map.put(overrides, :redact_sensitive, false)
    else
      overrides
    end
  :persistent_term.put({:jido_debug, instance}, %{level: level, overrides: overrides})
  :ok
end
```

---

## Changes to Existing Modules

### `Jido` (`lib/jido.ex`)

**`__using__` macro — add instance delegates:**

```elixir
def debug(level_or_pid \\ nil, opts \\ [])
def debug(nil, _opts), do: Jido.Debug.level(__MODULE__)
def debug(pid, level) when is_pid(pid), do: Jido.AgentServer.set_debug(pid, level != :off)
def debug(level, opts) when is_atom(level), do: Jido.Debug.enable(__MODULE__, level, opts)

def recent(pid, limit \\ 50), do: Jido.AgentServer.recent_events(pid, limit: limit)

def debug_status, do: Jido.Debug.status(__MODULE__)
```

**`__using__` macro — expose `__otp_app__/0` and thread otp_app:**

```elixir
# Generated by `use Jido, otp_app: :my_app`
@doc false
def __otp_app__, do: @otp_app

# In child_spec/1 and start_link/1:
opts = Keyword.put_new(opts, :otp_app, @otp_app)
```

**`Jido.init/1` — boot-time debug:**

```elixir
def init(opts) do
  name = Keyword.fetch!(opts, :name)

  if otp_app = opts[:otp_app] do
    Jido.Debug.maybe_enable_from_config(otp_app, name)
  end

  # ... existing children setup
end
```

**Top-level `Jido` module — default instance delegates:**

```elixir
def debug(level \\ nil, opts \\ [])
def debug(nil, _opts), do: Jido.Debug.level(Jido.Default)
def debug(level, opts), do: Jido.Debug.enable(Jido.Default, level, opts)
```

### `Jido.AgentServer` (`lib/jido/agent_server.ex`)

**Metadata threading — add `:jido_instance` everywhere:**

```elixir
defp build_signal_metadata(state, signal) do
  trace_metadata = TraceContext.to_telemetry_metadata()

  %{
    agent_id: state.id,
    agent_module: state.agent_module,
    signal_type: signal.type,
    jido_instance: state.jido
  }
  |> Map.merge(trace_metadata)
end
```

Same for directive metadata and queue overflow — anywhere `emit_telemetry/3` is called.

**Instance-aware debug recording:**

```elixir
# Replace direct state.debug checks with:
defp debug_mode?(state) do
  state.debug || Jido.Debug.enabled?(state.jido)
end
```

Use `debug_mode?/1` in `record_debug_event` guard and any other debug checks.

### `Jido.AgentServer.State` (`lib/jido/agent_server/state.ex`)

**Configurable ring buffer size.** Replace `@max_debug_events 50` with a per-state field defaulting to 500, resolved from `Observe.Config.debug_max_events(instance)` at agent init time. This keeps the hot path reading a struct field rather than a runtime config lookup.

```elixir
# In State struct definition, add:
debug_max_events: 500

# At agent init, set from config:
%State{... debug_max_events: Observe.Config.debug_max_events(jido_instance)}
```

Update `record_debug_event/3` to use the struct field and accept instance-level debug:

```elixir
def record_debug_event(%__MODULE__{} = state, type, data) do
  if state.debug || Jido.Debug.enabled?(state.jido) do
    event = %{at: System.monotonic_time(:millisecond), type: type, data: data}
    new_events = Enum.take([event | state.debug_events], state.debug_max_events)
    %{state | debug_events: new_events}
  else
    state
  end
end
```

### `Jido.Telemetry` (`lib/jido/telemetry.ex`)

**Drop GenServer. Convert to a plain module with idempotent `setup/0`.**

The current GenServer exists only to attach telemetry handlers in `init/1`. It holds no state and serves no requests. Replace with:

```elixir
defmodule Jido.Telemetry do
  @handler_id "jido-agent-metrics"

  @doc """
  Attaches telemetry handlers. Idempotent — safe to call multiple times
  (e.g., on supervisor restart). Called from `Jido.Application.start/2`.
  """
  def setup do
    :telemetry.detach(@handler_id)
  rescue
    _ -> :ok
  after
    :telemetry.attach_many(@handler_id, events(), &handle_event/4, nil)
  end

  # ... events/0, handle_event/4, etc. remain as module functions
end
```

**Automatic per-instance metrics scoping.** Expose `metrics/0` as a public API for host apps to wire into their reporter (e.g., `TelemetryMetricsPrometheus`). All metric definitions include `tags: [:jido_instance]` with a shared `tag_values` extractor that automatically pulls the instance from event metadata:

```elixir
@instance_tag_values fn meta -> %{jido_instance: meta[:jido_instance] || :global} end

def metrics do
  [
    Telemetry.Metrics.counter("jido.agent_server.signal.stop.duration",
      tags: [:jido_instance, :signal_type],
      tag_values: @instance_tag_values
    ),
    Telemetry.Metrics.summary("jido.agent_server.signal.stop.duration",
      tags: [:jido_instance, :signal_type],
      tag_values: @instance_tag_values,
      unit: {:native, :millisecond}
    ),
    # ... all other metrics follow the same pattern
  ]
end
```

Since Phase 1 guarantees `:jido_instance` in all event metadata, metrics are automatically scoped per-instance with no user configuration. The `:global` fallback handles events emitted outside an instance context. Host apps wire it up with one line:

```elixir
# In the host app's Application.start/2:
TelemetryMetricsPrometheus.init(Jido.Telemetry.metrics())
```

Remove the dead metric definitions from the old `init/1` — they were never consumed.

**Replace `Config.*()` calls with `Observe.Config.*(instance)`:**

Every handler clause extracts instance from metadata first:

```elixir
def handle_event([:jido, :agent_server, :signal, :stop], measurements, metadata, _config) do
  instance = metadata[:jido_instance]
  duration = Map.get(measurements, :duration, 0)
  duration_ms = Formatter.to_ms(duration)
  directive_count = metadata[:directive_count] || 0
  signal_type = metadata[:signal_type]

  cond do
    Observe.Config.trace_enabled?(instance) ->
      log_signal_stop(metadata, duration, directive_count)

    Observe.Config.debug_enabled?(instance) and
        interesting_signal?(instance, signal_type, duration_ms, directive_count, metadata) ->
      log_signal_stop(metadata, duration, directive_count)

    true ->
      :ok
  end
end
```

**Interestingness helpers gain `instance` parameter:**

```elixir
defp interesting_signal?(instance, signal_type, duration_ms, directive_count, metadata) do
  is_slow = duration_ms > Observe.Config.slow_signal_threshold_ms(instance)
  has_directives = directive_count > 0
  is_interesting_type = to_string(signal_type) in Observe.Config.interesting_signal_types(instance)
  has_error = metadata[:error] != nil

  is_slow or has_directives or is_interesting_type or has_error
end
```

**Delete dead code:** `span_agent_cmd/3` and `span_strategy/4` are never called. Remove them.

**Remove `compile_env`:** No longer needed once handlers go through `Observe.Config`.

**Reconcile trace metadata keys.** `Jido.Observe` uses `:jido_trace_id` / `:jido_span_id`, but `Jido.Telemetry` handlers log `metadata[:trace_id]` / `metadata[:span_id]`. Standardize on the `jido_`-prefixed keys to avoid collisions with other libraries' telemetry metadata.

### `Jido.Observe` (`lib/jido/observe.ex`)

**Instance-aware debug gating:**

`emit_debug_event/3` — extract instance from metadata, no API change:

```elixir
def emit_debug_event(event_prefix, measurements \\ %{}, metadata \\ %{}) do
  instance = Map.get(metadata, :jido_instance)

  if Observe.Config.debug_events_enabled?(instance) do
    :telemetry.execute(event_prefix, measurements, metadata)
  end

  :ok
end
```

**Instance-aware tracer:**

```elixir
defp tracer(metadata) when is_map(metadata) do
  instance = Map.get(metadata, :jido_instance)
  Observe.Config.tracer(instance)
end
```

Update `start_span/2` and `finish_span/2` to pass enriched metadata to tracer:

```elixir
def start_span(event_prefix, metadata) do
  enriched_metadata = enrich_with_correlation(metadata)

  # ...existing telemetry execute...

  tracer_ctx =
    try do
      tracer(enriched_metadata).span_start(event_prefix, enriched_metadata)
    rescue
      e -> Logger.warning("..."); nil
    end

  # ...
end
```

**Instance-aware redaction:**

```elixir
def redact(value, opts \\ []) do
  force_redact = Keyword.get(opts, :force_redact, false)
  instance = Keyword.get(opts, :jido_instance)
  should_redact = force_redact || Observe.Config.redact_sensitive?(instance)

  if should_redact, do: "[REDACTED]", else: value
end
```

### `Jido.Observe.Log` (`lib/jido/observe/log.ex`)

Extract instance from metadata keyword list — no API change:

```elixir
def log(level, message, metadata \\ []) do
  instance = Keyword.get(metadata, :jido_instance)
  threshold = Observe.Config.observe_log_level(instance)
  Jido.Util.cond_log(threshold, level, message, metadata)
end
```

### `Jido.Telemetry.Config` (`lib/jido/telemetry/config.ex`)

Deprecate all public functions. Delegate to `Observe.Config` with `nil` instance:

```elixir
@deprecated "Use Jido.Observe.Config.telemetry_log_level/1 instead"
def log_level, do: Jido.Observe.Config.telemetry_log_level(nil)

@deprecated "Use Jido.Observe.Config.trace_enabled?/1 instead"
def trace_enabled?, do: Jido.Observe.Config.trace_enabled?(nil)

# ... etc for all public functions
```

Remove `@compile_log_level` and the `Application.compile_env` call.

### `Jido.Application` (`lib/jido/application.ex`)

Remove `Jido.Telemetry` from the children list. Replace with a call to `Jido.Telemetry.setup()` before starting the supervision tree:

```elixir
def start(_type, _args) do
  Jido.Telemetry.setup()

  children = [
    # ... Jido.Telemetry is no longer a child
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
end
```

### Logger metadata guidance

**Note:** Jido is a library — it cannot enforce host app logger config. Document the following in observability guides as recommended setup:

```elixir
# In the host app's config/config.exs or config/dev.exs:
config :logger, :default_formatter,
  format: "[$level] $message $metadata\n",
  metadata: [:agent_id, :agent_module, :jido_instance]
```

---

## Implementation Phases

### Phase 1: Foundation (non-breaking, no behavior change)

| Step | What | Files |
|------|------|-------|
| 1.1 | Create `Jido.Observe.Config` with resolution logic (including `debug_max_events/1`, default 500) | `lib/jido/observe/config.ex` (new) |
| 1.2 | Add `__otp_app__/0` to `__using__` macro, thread `otp_app` through `start_link` | `lib/jido.ex` |
| 1.3 | Add `:jido_instance` to all AgentServer telemetry metadata | `lib/jido/agent_server.ex` |
| 1.4 | Add `debug_max_events` field to `AgentServer.State`, default from `Observe.Config` | `lib/jido/agent_server/state.ex` |
| 1.5 | Tests for `Observe.Config` (nil instance = global behavior) | `test/jido/observe/config_test.exs` (new) |

**Verify:** `mix test` passes. No behavior change. Events now carry `:jido_instance`.

### Phase 2: Rewire (behaviorally equivalent, now instance-capable)

| Step | What | Files |
|------|------|-------|
| 2.1 | Telemetry handlers use `Observe.Config.*(instance)` instead of `Config.*()` | `lib/jido/telemetry.ex` |
| 2.2 | Interestingness helpers accept `instance` | `lib/jido/telemetry.ex` |
| 2.3 | `Observe.emit_debug_event` gates via `Observe.Config.debug_events_enabled?(instance)` | `lib/jido/observe.ex` |
| 2.4 | `Observe` tracer resolution uses instance from metadata | `lib/jido/observe.ex` |
| 2.5 | `Observe.Log.log/3` extracts instance from metadata | `lib/jido/observe/log.ex` |
| 2.6 | `Observe.redact/2` accepts `:jido_instance` in opts | `lib/jido/observe.ex` |
| 2.7 | Reconcile trace metadata keys: standardize on `jido_trace_id`/`jido_span_id` | `lib/jido/telemetry.ex`, `lib/jido/observe.ex` |
| 2.8 | Tests: per-instance config overrides global | `test/jido/observe/config_test.exs` |

**Verify:** `mix test` passes. Behavior identical with no per-instance config set.

### Phase 3: Debug API

| Step | What | Files |
|------|------|-------|
| 3.1 | Implement `Jido.Debug` (persistent_term storage, enable/disable/override/reset) | `lib/jido/debug.ex` (new) |
| 3.2 | Add `debug/0,1,2`, `recent/2`, `debug_status/0` to `__using__` macro | `lib/jido.ex` |
| 3.3 | Add `debug/0,1,2` delegates on top-level `Jido` module | `lib/jido.ex` |
| 3.4 | Boot-time enablement in `Jido.init/1` | `lib/jido.ex` |
| 3.5 | Instance-aware debug recording in AgentServer.State (uses `state.debug_max_events`) | `lib/jido/agent_server/state.ex` |
| 3.6 | Tests for Debug enable/disable/override/reset, per-instance isolation | `test/jido/debug_test.exs` (new) |
| 3.7 | Integration test: `debug: true` in config → agents record events | `test/jido/debug_integration_test.exs` (new) |

**Verify:** `MyApp.Jido.debug(:on)` immediately affects telemetry verbosity and ring buffers for that instance only.

### Phase 4: Cleanup

| Step | What | Files |
|------|------|-------|
| 4.1 | Drop GenServer from `Jido.Telemetry`: convert to plain module with idempotent `setup/0` | `lib/jido/telemetry.ex` |
| 4.2 | Add `metrics/0` public API with automatic per-instance scoping via `tags`/`tag_values` | `lib/jido/telemetry.ex` |
| 4.3 | Remove `Jido.Telemetry` from supervision tree, call `setup/0` from `Application.start/2` | `lib/jido/application.ex` |
| 4.4 | Deprecate `Jido.Telemetry.Config` (delegate to `Observe.Config(nil)`) | `lib/jido/telemetry/config.ex` |
| 4.5 | Remove `Application.compile_env` from `Telemetry.Config` | `lib/jido/telemetry/config.ex` |
| 4.6 | Delete `span_agent_cmd/3` and `span_strategy/4` (dead code) | `lib/jido/telemetry.ex` |
| 4.7 | Update observability guides (include logger metadata guidance for host apps) | `guides/observability-intro.md`, `guides/observability.md`, `guides/runtime.md` |

**Verify:** `mix quality` passes. No warnings from deprecated usage within jido itself.

---

## Files Summary

| File | Change | Phase |
|------|--------|-------|
| `lib/jido/observe/config.ex` | **New.** Unified config resolver with `debug_max_events/1`. ~130 lines. | 1 |
| `lib/jido/debug.ex` | **New.** Per-instance debug state. ~100 lines. | 3 |
| `lib/jido.ex` | Add `__otp_app__/0`, thread otp_app, add debug delegates. ~30 lines changed. | 1, 3 |
| `lib/jido/agent_server.ex` | Add `:jido_instance` to metadata, instance-aware debug check. ~15 lines. | 1, 3 |
| `lib/jido/agent_server/state.ex` | Add `debug_max_events` field (default 500), instance-aware `record_debug_event`. ~10 lines. | 1, 3 |
| `lib/jido/telemetry.ex` | Drop GenServer, add idempotent `setup/0`, add `metrics/0` with per-instance tags, use `Observe.Config`, delete dead code, reconcile trace keys. ~80 lines changed. | 2, 4 |
| `lib/jido/telemetry/config.ex` | Deprecate, delegate, remove compile_env. ~30 lines changed. | 4 |
| `lib/jido/observe.ex` | Instance-aware debug gating, tracer, redact. ~15 lines changed. | 2 |
| `lib/jido/observe/log.ex` | Extract instance from metadata. ~3 lines changed. | 2 |
| `lib/jido/application.ex` | Remove `Jido.Telemetry` child, call `Jido.Telemetry.setup()`. ~3 lines changed. | 4 |
| Tests (new) | `observe/config_test.exs`, `debug_test.exs`, `debug_integration_test.exs`. ~200 lines. | 1-3 |
| Guides | Update observability docs (include logger metadata guidance for host apps). | 4 |

---

## Backward Compatibility

| Existing API/Config | V2 Behavior |
|---------------------|-------------|
| `config :jido, :telemetry, log_level: :debug` | Still works. Becomes global default (resolution step 3). |
| `config :jido, :observability, debug_events: :all` | Still works. Becomes global default (resolution step 3). |
| `AgentServer.start_link(debug: true)` | Still works. Per-agent toggle unchanged. |
| `AgentServer.set_debug(pid, true)` | Still works. |
| `AgentServer.recent_events(pid)` | Still works. |
| `Jido.Telemetry.Config.log_level()` | Deprecated. Delegates to `Observe.Config.telemetry_log_level(nil)`. |
| `Jido.Observe.debug_enabled?()` | Still works. Delegates to `Observe.Config.debug_events_enabled?(nil)`. |

Zero breaking changes. All existing config, APIs, and patterns continue to work.

---

## Testing Strategy

1. **`Observe.Config` unit tests:** Verify 4-level resolution order. Test with nil instance, known instance with per-instance config, instance without per-instance config (falls to global), debug override active. Test `debug_max_events/1` defaults to 500.
2. **`Jido.Debug` unit tests:** enable/disable/level/override/reset. Verify persistent_term isolation between instances. Verify `maybe_enable_from_config`.
3. **Telemetry handler integration:** Emit events with different `:jido_instance` values, verify correct log_level/interestingness applied per-instance.
4. **Telemetry metrics:** Verify `metrics/0` returns definitions with `tags: [:jido_instance]` and `tag_values` extractor that falls back to `:global`.
5. **AgentServer integration:** Start instance with `debug: true` in config, verify all agents record debug events without per-agent opt-in.
6. **Test hygiene:** `Jido.Debug.reset(instance)` in `setup` blocks to prevent cross-test leakage.

---

## Resolved Decisions

1. **Ring buffer size.** Configurable via `Observe.Config.debug_max_events/1`, default **500**. Stored on `AgentServer.State` struct at init time so the hot path reads a struct field, not a runtime config lookup.

2. **Logger level side-effect.** `Jido.Debug.enable/3` does **not** call `Logger.configure/1`. That is global and would affect all libraries. Document clearly: "ensure `config :logger, level: :debug` in your dev.exs."

3. **`debug/1` overload.** `MyApp.Jido.debug(:on)` vs `MyApp.Jido.debug(pid)` — distinguishable by type (atom vs pid). If string agent IDs are needed later, use a separate function name (e.g., `debug_agent/2`).

4. **`Jido.Telemetry` drops GenServer.** Becomes a plain module with idempotent `setup/0` (detach-then-attach). Called from `Jido.Application.start/2`.

5. **Metrics scoping is automatic.** All metric definitions include `tags: [:jido_instance]` and a shared `tag_values` extractor. Per-instance series appear in reporters with no user configuration. `metrics/0` is exposed as public API for host apps to wire into their reporter.

6. **No `Observe.Config.Registry`.** Per-instance config resolves via `instance.__otp_app__/0` (generated by `use Jido`). `Jido.Default` falls through to global config via `function_exported?/3` guard.

7. **Trace metadata keys.** Standardize on `jido_trace_id`/`jido_span_id` across both `Jido.Observe` and `Jido.Telemetry` to avoid naming collisions with other libraries.
