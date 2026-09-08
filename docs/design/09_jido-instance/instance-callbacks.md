# Jido instance callbacks

> Supporting Jido instance design. This document is pending approval.

## Question

Should a module that uses `Jido` have callbacks for instance-level setup and
policy?

A Jido instance is primarily a supervision boundary. Most runtime events must
not call application code in the instance supervisor. Supervised children,
Telemetry events, Agent Plugins, and Directives already own most extension
needs.

## Current state

`use Jido` generates configuration, startup, Agent management, persistence,
and debug functions. An application can override `config/1`. The internal
`Jido.init/1` callback always starts the standard Jido supervision tree:

- Task supervisor
- Registry
- Runtime store
- Spawn registry
- Dynamic Agent supervisor

The instance module cannot add instance-owned children to this tree. It also
has no instance-wide Agent admission policy.

## Most useful callback

The first callback to consider is `children/1`:

```elixir
@callback children(config :: keyword()) :: [Supervisor.child_spec()]
```

Example:

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app

  @impl true
  def children(config) do
    [
      {MyApp.AgentCatalog, jido: __MODULE__},
      {MyApp.Reconciler,
       jido: __MODULE__, interval: config[:reconcile_interval]}
    ]
  end
end
```

This callback lets an application add services that belong to one Jido
instance. OTP then owns their startup, restart, readiness, and cleanup.

The contract must define where custom children are placed in the supervision
tree. A safe default is to start them after the standard registry and runtime
services. The callback must only return child specifications. It must not start
processes.

## Other callbacks to evaluate

### Configuration initialization

An optional initialization callback could validate or derive configuration:

```elixir
@callback init(config :: keyword()) ::
  {:ok, keyword()} | {:stop, term()}
```

Valid work includes:

- Validate instance configuration.
- Calculate runtime settings.
- Select configured adapters.
- Stop startup before children start.

The callback must not make network requests, start processes, or do application
work. A supervised child must do that work.

The name `init/1` can cause confusion with the internal Supervisor callback.
`configure/1` can make the ownership clearer.

### Agent admission

An instance-wide admission callback could apply policy before an Agent Server
starts:

```elixir
@callback admit_agent(agent :: Jido.Agent.t(), context :: map()) ::
  :ok | {:error, term()}
```

Possible uses include:

- Permit only selected Agent modules.
- Require instance metadata.
- Enforce tenant or resource limits.
- Reject an Agent before it enters the supervision tree.

This callback needs a strict failure contract. It must also define whether it
runs before or after persistence restore. A separate policy module can be
better than an instance callback if admission becomes complex or needs state.

## Events that should not be callbacks

Use the existing owner for these events:

| Event or need | Owner |
| --- | --- |
| All instance services are ready | Supervised bootstrap child |
| Instance cleanup | Child `terminate/2` and OTP shutdown |
| Agent activation, restore, stop, or crash | Telemetry |
| Turn commit or failure | Agent Telemetry |
| Plugin runtime health | Telemetry or Plugin lifecycle API |
| Per-Agent behavior | Agent Plugin |
| Work after commit | Directive |

Do not add general `after_start`, `before_stop`, `agent_started`, or
`agent_stopped` callbacks. These callbacks create unclear blocking, ordering,
and failure behavior. Telemetry and supervised processes cover these needs.

## Small possible contract

If all three needs prove valid, the instance behavior could have this shape:

```elixir
@callback configure(config()) :: {:ok, config()} | {:stop, term()}
@callback children(config()) :: [Supervisor.child_spec()]
@callback admit_agent(Jido.Agent.t(), context()) :: :ok | {:error, term()}

@optional_callbacks configure: 1, children: 1, admit_agent: 2
```

Start with `children/1`. It is the most direct OTP extension and covers most
instance lifecycle needs. Add the other callbacks only when a concrete use
case needs their decision point and failure rules.

## Open questions

1. Do custom children start inside the Jido supervisor or in a nested custom
   supervisor?
2. Can custom children depend on all standard Jido services during their
   `init/1` functions?
3. Must `children/1` be a pure function of final instance configuration?
4. Does Agent admission run before restore, after restore, or at both points?
5. How does admission work for remote child placement and `thaw/3`?
6. Does a plain `Jido.start_link/1` instance support these callbacks, or only a
   module that uses `Jido`?
