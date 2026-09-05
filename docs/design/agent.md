> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Agent

[Design overview](README.md) | Next: [Turn evaluation](turn-evaluation.md)

- Depends on: Signals, Actions, Flows, Plugins, and Zoi schemas.
- Defines: the immutable Agent value, checkpoint value, public data API, and
  custom Agent module contract.

## Model

An Agent module declares its definition revision, domain schema, Signal routes,
Plugins, and metadata. `new` combines this static configuration with an ID,
validated domain state, and validated Plugin state.

Every `%Jido.Agent{}` is a complete Agent. There is no definition form and no
partly initialized form.

`Jido.Agent` is a Zoi-backed public struct. Its only purpose is to hold one
complete immutable Agent value. Construction and every public replacement
operation validate the complete struct.

## Agent shape

```elixir
%Jido.Agent{
  # Static configuration copied from the Agent module
  module: MyApp.OrderAgent,
  definition_revision: 1,
  name: "order_agent",
  description: "Processes an order",
  schema: domain_state_schema,
  routes: [
    {"order.create", CreateOrder},
    {"order.cancel", CancelOrder}
  ],
  plugins: [
    %Jido.Plugin{
      id: :heartbeat,
      module: Jido.Plugin.Heartbeat,
      name: "heartbeat",
      description: "Sends periodic Signals",
      options_schema: heartbeat_options_schema,
      options: %{interval: 5_000},
      state_schema: nil,
      directives: [],
      runtime: Jido.Plugin.Heartbeat.Runtime
    },
    %Jido.Plugin{
      id: :scheduler,
      module: Jido.Plugin.Scheduler,
      name: "scheduler",
      description: "Schedules delayed and recurring Signals",
      options_schema: scheduler_options_schema,
      options: %{timezone: "Etc/UTC"},
      state_schema: scheduler_state_schema,
      directives: [
        Jido.Plugin.Scheduler.Schedule,
        Jido.Plugin.Scheduler.Cancel
      ],
      runtime: Jido.Plugin.Scheduler.Runtime
    }
  ],
  metadata: %{},

  # Identity and portable state
  id: "order-123",
  state: %{
    status: :pending,
    total: 100
  },
  plugin_state: %{
    scheduler: %{
      cron: %{}
    }
  }
}
```

`schema` validates only `state`. Each Plugin `state_schema` validates its entry
in `plugin_state`. A stateless Plugin has no entry. Plugin IDs are unique within
one Agent, and the Plugin module can be the default ID.

Construction applies schema defaults to both state classes. It does not start a
runtime, run a Plugin mount callback, or produce Directives.

`definition_revision` is a required positive integer owned by the Agent
module. The module must increase it when any normalized static configuration
changes. This includes the domain schema, routes, Plugin list, Plugin options,
metadata, name, or description. Core does not construct an Agent from an
unowned runtime definition.

## Route resolution

An Agent declares ordered Signal routes. Jido normalizes them with
`Jido.Signal.Router` and uses this deterministic precedence:

1. Exact paths.
2. Paths with `*`.
3. Paths with `**`.
4. More complex patterns.
5. Higher explicit priority.
6. Earlier declaration order.

The Signal Router returns all matches in precedence order. `Jido.Agent`
selects the first match and ignores lower-ranked matches. It returns a
structured routing error when no route matches.

The Turn Evaluator resolves this route from the original source Signal before
it calls any Plugin preparation callback. The selected executable and route
parameters then stay fixed for the complete Turn. A prepared effective Signal
is input to that executable. It does not cause another route lookup.

This permits specific routes with a catch-all fallback:

```elixir
routes: [
  {"order.create", CreateOrder},
  {"order.cancel", CancelOrder},
  {"**", DynamicOrderFlow}
]
```

An exact route wins before the catch-all route. An Agent that needs all routing
to be dynamic can declare only `{"**", DynamicOrderFlow}`. The routed Action or
Flow owns the dynamic domain decision.

Checkpoints save `state` and `plugin_state` together. Jido commits them
atomically.

## Portable state contract

Agent domain state and Plugin state use one recursive portable-term contract.
It permits nil, booleans, atoms, numbers, binaries, proper lists, tuples, Maps,
and structs when every nested value is also portable. It rejects PIDs, ports,
references, functions, improper lists, and non-byte-aligned bitstrings.

Jido applies this check after each state schema check during construction,
state replacement, candidate validation, checkpoint construction, and restore.
A schema that accepts `Zoi.any()` does not bypass the portable-term check. A
failure reports the exact state path in a defined ValidationError.

The rule applies to instance data. Static module configuration can contain
external function captures for declared route matches because Jido rebuilds
that configuration from the versioned Agent module during restore.

## Checkpoint shape

Jido uses one fixed portable checkpoint value:

```elixir
%Jido.Agent.Checkpoint{
  version: 1,
  agent_module: MyApp.OrderAgent,
  definition_revision: 1,
  agent_id: "order-123",
  state: %{
    status: :pending,
    total: 100
  },
  plugin_state: %{
    scheduler: %{cron: %{}}
  }
}
```

`version` identifies the checkpoint format version. `definition_revision`
identifies the exact module-owned Agent definition that validates and executes
the saved state. The Agent Server keeps its committed state version in the
persistence record that contains this checkpoint. These three versions have
different purposes and are not interchangeable.

`Jido.Agent.Checkpoint` is a Zoi-backed public struct. Its only purpose is to
hold the portable data required to reconstruct one Agent. The Agent's domain
schema validates `state`, and each declared Plugin schema validates its owned
`plugin_state` entry.

The checkpoint keeps `agent_id` because `Jido.Agent.checkpoint/1` also works
without a live Jido instance. It does not contain namespace or partition.
`Jido.Persistence.Record` adds the complete Agent Ref and validates that both
IDs match.

Checkpoint and restore behavior is owned by `Jido.Agent`. Agent modules cannot
replace the checkpoint format. Storage encoding, encryption, and compression
belong to the instance persistence implementation.

`checkpoint/1` succeeds only when the Agent module exports its normalized
definition, the definition has a positive revision, and the Agent's complete
static configuration equals that definition. A revision value by itself does
not prove module ownership.

`restore/2` first confirms that the supplied module equals `agent_module` and
that its current normalized definition has the saved `definition_revision`.
It then rebuilds the complete static configuration from that module and
validates `state` and `plugin_state`. A missing module or revision mismatch
returns a defined restore error. Core does not migrate a checkpoint or restore
it under a different declared revision.

The Agent contains no PID, timer, task, monitor, or runtime handle.

## `Jido.Agent` API

The public data API is:

| Function | Purpose |
| --- | --- |
| `new/2` | Build a complete Agent from an Agent module and options. |
| `new!/2` | Build a complete Agent or raise. |
| `validate/1` | Validate the complete Agent. |
| `state/1` | Return the complete domain state. |
| `fetch_state/2` | Fetch one top-level domain state field. |
| `plugin_state/2` | Return the complete state for one Plugin. |
| `fetch_plugin_state/3` | Fetch one top-level field from one Plugin state. |
| `replace_state/2` | Replace and validate the complete domain state. |
| `replace_plugin_state/3` | Replace and validate one complete Plugin state entry. |
| `cmd/3` | Evaluate one Turn without a live Server. |
| `checkpoint/1` | Build a portable checkpoint for a versioned module-owned Agent. |
| `restore/2` | Restore an Agent only under the checkpoint's exact module definition revision. |

The function signatures are:

```elixir
Jido.Agent.new(agent_module, opts \\ [])
Jido.Agent.new!(agent_module, opts \\ [])
Jido.Agent.validate(agent)
Jido.Agent.state(agent)
Jido.Agent.fetch_state(agent, key)
Jido.Agent.plugin_state(agent, plugin_id)
Jido.Agent.fetch_plugin_state(agent, plugin_id, key)
Jido.Agent.replace_state(agent, complete_domain_state)
Jido.Agent.replace_plugin_state(agent, plugin_id, complete_plugin_state)
Jido.Agent.cmd(agent, signal, opts \\ [])
Jido.Agent.checkpoint(agent)
Jido.Agent.restore(agent_module, checkpoint)
```

Construction, validation, replacement, command, checkpoint, and restore
failures return a defined `Jido.Error.t()`. `cmd/3` returns
`{:ok, agent, directives}` or `{:error, Jido.Error.t()}`. `state/1` returns the
complete domain state map. `plugin_state/2` returns the complete state map for
one declared stateful Plugin. `fetch_state/2` and `fetch_plugin_state/3` are the
explicit Map protocol exceptions: they return `{:ok, value}` or `:error`.

```elixir
Jido.Agent.state(agent)
# => %{status: :pending, total: 100}

Jido.Agent.fetch_state(agent, :total)
# => {:ok, 100}

Jido.Agent.plugin_state(agent, :scheduler)
# => %{cron: %{}}

Jido.Agent.fetch_plugin_state(agent, :scheduler, :cron)
# => {:ok, %{}}
```

The normal construction call is:

```elixir
Jido.Agent.new(MyApp.Counter, id: "counter-1")
# => {:ok, %Jido.Agent{}}
```

`new/2` and the generated module `new/1` use the same tagged result. `new!`
provides the direct form. There is no `instantiate` or ambiguous `set`.

`replace_state/2` accepts one complete domain state map. It does not merge a
patch. `replace_plugin_state/3` accepts one complete state value for one
declared stateful Plugin. It rejects unknown or stateless Plugin IDs. Both
functions validate the result and return a new Agent.

Normal domain and Plugin state changes go through `cmd/3`. During a command,
only the Action or Flow can change domain state, and only the owning Plugin can
change its Plugin state. The explicit replacement functions are direct
immutable data operations. They do not run a command or produce Directives.

## Serialization

`Jido.Agent` has no `to_map/1` or `from_map/1` API. The complete Agent contains
modules, Zoi schemas, routes, and executable configuration. A plain Agent Map
is not a portable serialization format.

Core has no Agent authoring serialization boundary. A future authoring package
can define a trusted external document, but it must resolve the document to a
versioned Agent module and use `Jido.Agent.new/2`. `Jido.Agent.Checkpoint` is
only the portable instance-state value for persistence. It is not an authoring
document.

## Defining a custom Agent

`use Jido.Agent` defines one reusable Agent type:

```elixir
defmodule MyApp.Counter.Increment do
  use Jido.Action,
    name: "counter_increment",
    schema: Zoi.object(%{
      amount: Zoi.integer() |> Zoi.default(1)
    })

  @impl Jido.Action
  def run(%{amount: amount}, context) do
    next_state = %{
      context.agent_state
      | count: context.agent_state.count + amount
    }

    {:ok, next_state}
  end
end

defmodule MyApp.Counter do
  use Jido.Agent,
    definition_revision: 1,
    name: "counter",
    description: "Counts received increments",
    schema: Zoi.object(%{
      count: Zoi.integer() |> Zoi.default(0)
    }),
    routes: [
      {"counter.increment", MyApp.Counter.Increment}
    ],
    plugins: [],
    metadata: %{category: :example}
end
```

The generated module API is:

```elixir
{:ok, agent} = MyApp.Counter.new(id: "counter-1")

signal =
  Jido.Signal.new!(
    "counter.increment",
    %{amount: 2},
    source: "/example"
  )

{:ok, next_agent, directives} = MyApp.Counter.cmd(agent, signal)
```

`use Jido.Agent` provides only the main data API:

```elixir
MyApp.Counter.new/0
MyApp.Counter.new/1
MyApp.Counter.new!/0
MyApp.Counter.new!/1
MyApp.Counter.cmd/2
MyApp.Counter.cmd/3
```

These functions are thin delegates:

```elixir
MyApp.Counter.new(opts) == Jido.Agent.new(MyApp.Counter, opts)
MyApp.Counter.cmd(agent, signal, opts) == Jido.Agent.cmd(agent, signal, opts)
```

The module exposes its validated static configuration through the internal
`__agent_config__/0` function. This is framework metadata, not another Agent
data type.

The Agent module has no routing, persistence, or process lifecycle callback.
Jido resolves its declared routes. Domain selection and branching belong to
the routed Action or Flow.

The Agent module also has no general before-command or after-command hook.
Plugins use their declared transition points instead.

The Agent module has no outbound callback such as `handle_result/2` or
`after_signal/2`. The return is a value, not another callback point. A pure
command returns the candidate Agent and Directives. A live instance Result
returns the committed Agent. The internal Server handles Directives and runtime
observation after commit.
