# Configuration

Jido configuration has three scopes: the Jido instance, one Agent actor, and
observability. Keep durable policy at the instance boundary and pass actor
options only when one actor needs different behavior.

## Configure a Jido instance

Define one named Jido instance for an application and add it to the application
supervision tree.

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    persistence: {Jido.Persistence.ETS, table: :my_app_agents}
end
```

```elixir
children = [MyApp.Jido]
Supervisor.start_link(children, strategy: :one_for_one)
```

The `:otp_app` value tells the generated module where to read its runtime
configuration. The optional `:persistence` value defines the default adapter
for actors in this instance.

Set instance options in application configuration:

```elixir
config :my_app, MyApp.Jido,
  max_tasks: 2_000,
  telemetry: [
    log_level: :info,
    slow_signal_threshold_ms: 25,
    slow_directive_threshold_ms: 10
  ],
  observability: [
    redact_sensitive: true,
    tracer: MyApp.JidoTracer,
    tracer_failure_mode: :warn
  ]
```

Options passed to `MyApp.Jido.start_link/1` override application configuration.
The default `:max_tasks` value is `1_000`.

## Configure one actor

Pass actor options to `start_agent/2`.

```elixir
{:ok, server} =
  MyApp.Jido.start_agent(MyAgent,
    id: "agent-42",
    partition: :north,
    max_postponed_signals: 200,
    max_directives_per_turn: 20,
    directive_timeout: 3_000,
    idle_timeout: 60_000,
    restore: :if_found,
    error_policy: :stop_on_error,
    debug: false
  )
```

Important actor defaults are:

| Option | Default | Purpose |
| --- | --- | --- |
| `:max_postponed_signals` | `1_000` | Limit queued Signals while one Turn is active. |
| `:max_directives_per_turn` | `:infinity` | Limit Directive work from one Turn. |
| `:directive_timeout` | `5_000` | Limit Plugin and external Directive handling. |
| `:idle_timeout` | `:infinity` | Stop a pool-owned idle actor after this time. |
| `:restore` | `:if_found` | Select durable restore behavior. |
| `:error_policy` | `:log_only` | Select server behavior after a failed Turn. |
| `:on_parent_death` | `:stop` | Select child behavior when its logical parent ends. |
| `:debug` | `false` | Enable the local debug event buffer. |
| `:debug_max_events` | `500` | Limit the debug event buffer. |

Use `:partition` when the same Agent ID must exist in separate registry
namespaces. Use the same partition for lookup, stop, persistence, hibernate, and
thaw operations.

The supported error policies are `:log_only`, `:stop_on_error`,
`{:max_errors, count}`, `{:emit_signal, dispatch}`, or a function with arity two.

## Configure observability

Observability settings resolve in this order:

1. A runtime `Jido.Debug` override for the instance
2. Per-instance application configuration
3. Global `:jido` application configuration
4. The Jido default

Runtime debug mode is useful during investigation:

```elixir
:ok = MyApp.Jido.debug(:on)
status = MyApp.Jido.debug_status()
:ok = MyApp.Jido.debug(:off)
```

Do not depend on a debug override as permanent production configuration.

## Keep ownership clear

Jido validates its own actor and observability options. A Plugin validates its
own options. Jido Action controls Action execution options. Jido Signal controls
bus and dispatch options. Keep each option at the package boundary that owns
its contract.

Next, run [Observe Agent Turns](observe-agent-turns.livemd) to inspect semantic
Turn events.
