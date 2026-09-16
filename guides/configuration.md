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
    namespace: "my-app/primary",
    persistence: {Jido.Persistence.ETS, table: :my_app_agents}
end
```

```elixir
children = [MyApp.Jido]
Supervisor.start_link(children, strategy: :one_for_one)
```

The `:otp_app` value tells the generated module where to read its runtime
configuration. The optional `:namespace` value enables stable Agent Ref
operations. It must be a nonempty binary and must be unique among live local
instances on one Erlang node. The optional `:persistence` value defines the
default adapter for actors in this instance.

For shared Bedrock persistence, use a host repo created with `Bedrock.Repo`:

```elixir
persistence:
  {Jido.Persistence.Bedrock,
   repo: MyApp.BedrockRepo,
   prefix: "my-app:jido:",
   timeout_in_ms: 5_000}
```

The host application must add Bedrock `0.7.2` or later `0.7.x` and constrain
Bedrock Raft to `~> 0.10.0`. It must configure the durability profile and supervise
the Bedrock cluster before the Jido instance. See
[Persistence Adapters](persistence-adapters.html) for the transaction and
failure rules.

Set instance options in application configuration:

```elixir
config :my_app, MyApp.Jido,
  max_tasks: 2_000,
  debug: false
```

Options passed to `MyApp.Jido.start_link/1` override application configuration.
The default `:max_tasks` value is `1_000`. Jido validates `:name`, `:otp_app`,
`:namespace`, `:max_tasks`, `:persistence`, and `:debug` before it starts any
instance child. `:debug` accepts `false`, `true`, or `:verbose`. Runtime options
override application configuration. Other unknown instance keys fail
validation.

`max_tasks` limits only children of the instance Task Supervisor. It does not
limit Agent Server mailboxes, postponed Signals, or Plugin runtime processes.

## Configure one actor

Pass actor options to `start_agent/2`.

```elixir
{:ok, server} =
  MyApp.Jido.start_agent(MyAgent,
    id: "agent-42",
    partition: :north,
    max_postponed_signals: 200,
    turn_timeout: 10_000,
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
| `:turn_timeout` | `5_000` | Limit active pre-commit admission and candidate evaluation. |
| `:max_directives_per_turn` | `:infinity` | Limit Directive work from one Turn. |
| `:directive_timeout` | `5_000` | Limit Plugin admission, each commit notification, and each Directive dispatch. Notifications use `5_000` when this is `:infinity`. |
| `:idle_timeout` | `:infinity` | Stop a pool-owned idle actor after this time. |
| `:restore` | `:if_found` | Select durable restore behavior. |
| `:error_policy` | `:log_only` | Select server behavior after a failed Turn. |
| `:on_parent_death` | `:stop` | Select child behavior when its logical parent ends. |
| `:debug` | `false` | Enable the local debug event buffer. |
| `:debug_max_events` | `500` | Set a positive limit for the safe debug summary buffer. |

Use `:partition` when the same Agent ID must exist in separate registry
namespaces. Use the same partition for lookup, stop, persistence, hibernate, and
thaw operations.

The supported error policies are `:log_only`, `:stop_on_error`,
`{:max_errors, count}`, `{:emit_signal, dispatch}`, or a function with arity two.
They apply to ordinary Turn and Directive failures. A required persistence
write error always stops that activation, even when its configured policy would
continue.

## Configure observability

Use the Jido instance debug level to change semantic log detail during an
investigation:

```elixir
:ok = MyApp.Jido.debug(:on)
status = MyApp.Jido.debug_status()
:ok = MyApp.Jido.debug(:off)
```

Do not depend on a debug override as permanent production configuration.

Configure bounded semantic logs globally:

```elixir
config :jido, :telemetry,
  semantic_log_mode: :interesting,
  semantic_slow_threshold_ms: 250
```

The semantic modes are `:off`, `:errors`, `:interesting`, and `:all`.
`Jido.Telemetry.metrics/0` returns the low-cardinality semantic metric set.

The instance debug setting has priority for events from that Jido instance.
`:on` selects `:interesting`, and `:verbose` selects `:all`.

This instance setting does not enable the bounded event buffer for an Agent.
Use the Agent `:debug` option or `Jido.AgentServer.set_debug/3` for that buffer.
The semantic metadata allowlist applies in all debug modes.

OpenTelemetry is optional. A host that uses it must add both
`opentelemetry_api` and an OpenTelemetry SDK. To disable the Jido mapping while
the SDK remains active, use:

```elixir
config :jido, :opentelemetry, enabled: false
```

Use `Jido.Telemetry.open_telemetry?/0` to check if Jido has an active SDK
tracer. Jido does not start the SDK or configure its sampler or exporter.

## Keep ownership clear

Jido validates its own actor and observability options. A Plugin validates its
own options. Jido Action controls Action execution options. Jido Signal controls
bus and dispatch options. Keep each option at the package boundary that owns
its contract.

Next, run [Observe Agent Turns](observe-agent-turns.livemd) to inspect semantic
Turn events. See [Runtime State and Debugging](runtime-state-and-debugging.livemd)
for live inspection and the Agent event buffer. See
[Telemetry, Tracing, and Logs](telemetry-tracing-and-logs.md) for the complete
production observation contract.
