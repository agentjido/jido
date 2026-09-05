> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Plugins

[Design overview](README.md) | Previous: [Turn evaluation](turn-evaluation.md) | Next: [Agent Server](agent-server.md)

- Depends on: Agent state ownership and executable evaluation.
- Defines: the Plugin value, configuration API, owned state, callback values,
  and pure command callbacks.

## Model

A Plugin is an optional Agent component. It can own state, run supervised
processes, prepare commands, contribute to successful transitions, produce
Signals, and handle owned Directives.

The Plugin value declares:

- Module, stable instance ID, name, and description.
- Options schema and validated options.
- Zero or one owned state schema.
- Zero or more observed top-level Agent state fields.
- Zero or more owned Directive types.
- Zero or one supervised runtime module.

Each Plugin ID owns one entry in `Agent.plugin_state`. Directive types also have
one Plugin owner. The v3 spike starts with at most one Plugin value for each
Plugin module. This keeps Directive ownership and runtime lookup unambiguous.

`Jido.Plugin` is the only public Plugin configuration type. It provides the
`%Jido.Plugin{}` struct, constructors, behavior, and `use Jido.Plugin` macro.
There is no separate Plugin configuration type.

## Plugin module shape

A Plugin module declares static configuration and two pure command callbacks:

```elixir
defmodule MyApp.SchedulerPlugin do
  use Jido.Plugin,
    name: "scheduler",
    description: "Schedules delayed and recurring Signals",
    options_schema:
      Zoi.object(%{
        timezone: Zoi.string() |> Zoi.default("Etc/UTC")
      }),
    state_schema:
      Zoi.object(%{
        cron: Zoi.map(Zoi.any(), Zoi.any()) |> Zoi.default(%{})
      }),
    observes: [],
    directives: [
      MyApp.SchedulerPlugin.Schedule,
      MyApp.SchedulerPlugin.Cron,
      MyApp.SchedulerPlugin.Cancel
    ],
    runtime: MyApp.SchedulerPlugin.Runtime

  alias Jido.Plugin.{Command, Context, Contribution, Transition}
  alias MyApp.SchedulerPlugin.{Cancel, Cron}

  @impl Jido.Plugin
  def prepare(%Command{} = command, %Context{}) do
    {:ok, command}
  end

  @impl Jido.Plugin
  def contribute(
        %Transition{directives: directives},
        %Context{plugin_state: %{cron: cron}}
      ) do
    next_cron =
      Enum.reduce(directives, cron, fn
        %Cron{job_id: id} = directive, acc ->
          Map.put(acc, id, %{
            cron: directive.cron,
            signal: directive.signal,
            timezone: directive.timezone
          })

        %Cancel{job_id: id}, acc -> Map.delete(acc, id)
        _directive, acc -> acc
      end)

    {:ok,
     %Contribution{
       plugin_state: %{cron: next_cron},
       directives: []
     }}
  end
end
```

The module declaration is static. The `runtime` entry is optional. A stateless
Plugin sets `state_schema: nil`. A Plugin with no owned Directive types uses an
empty list. `observes` lists top-level Agent domain-state fields and defaults
to an empty list.

Directive dispatch does not by itself require a runtime process. The current
SDK accepts a Plugin with `directives/1`, `validate_directive/2`, and `dispatch/4`
but no `child_spec/1`. Its dispatch callback receives `nil` for the runtime and
runs in a Server-owned supervised task. When a runtime is declared, dispatch
requires that runtime to be available. Both forms keep the same validation,
commit, ordering, timeout, and failure contracts.

Current dispatch context includes the Turn's transient caller and Plugin
context. It is not stored in the Directive or checkpoint. Recovery must obtain
its dependencies from configuration or restored resources, not a prior caller's
process handle. The declaration and callback changes proposed below must retain
these ownership and lifetime rules.

`use Jido.Plugin` generates this module API:

```elixir
MyApp.SchedulerPlugin.new(opts \\ [])
MyApp.SchedulerPlugin.new!(opts \\ [])
```

These functions use the core constructor:

```elixir
Jido.Plugin.new(MyApp.SchedulerPlugin, opts \\ [])
Jido.Plugin.new!(MyApp.SchedulerPlugin, opts \\ [])
```

`new/1` validates instance options and returns `{:ok, %Jido.Plugin{}}`.
`new!/1` returns the Plugin or raises a structured validation error. These
functions do not start a runtime.

## Plugin data shape

The Agent stores normalized Plugin instances as `%Jido.Plugin{}` values:

```elixir
%Jido.Plugin{
  id: :scheduler,
  module: MyApp.SchedulerPlugin,
  name: "scheduler",
  description: "Schedules delayed and recurring Signals",
  options_schema: scheduler_options_schema,
  options: %{timezone: "Etc/UTC"},
  state_schema: scheduler_state_schema,
  observes: [],
  directives: [
    MyApp.SchedulerPlugin.Schedule,
    MyApp.SchedulerPlugin.Cron,
    MyApp.SchedulerPlugin.Cancel
  ],
  runtime: MyApp.SchedulerPlugin.Runtime
}
```

An Agent declaration creates this value with:

```elixir
MyApp.SchedulerPlugin.new!(
  id: :scheduler,
  options: %{timezone: "Etc/UTC"}
)
```

`id` is a stable atom or string. It is unique in one Agent and is the key for
`Agent.plugin_state`. The Plugin module is the default ID. An explicit ID gives
the instance a shorter or domain-specific state key. It does not permit a
second Plugin value for the same Plugin module in the v3 spike.

`name`, `description`, both schemas, observed state fields, Directive modules,
and the runtime module come from the Plugin module. Only `id` and validated
`options` vary by Agent instance. `%Jido.Plugin{}` contains configuration only.
It contains no PID, timer, monitor, or runtime reference.

`Jido.Plugin` is a Zoi-backed public struct. Its only purpose is to hold one
complete validated capability configuration. Cross-field validation checks
identity, schema ownership, Directive ownership, and runtime module
compatibility. `observes` is a unique list of top-level field names. Agent
construction confirms that each name exists in the Agent state schema.

## Plugin state

`Agent.state` and `Agent.plugin_state` are separate contracts. The Action or
Flow sees and returns domain state only. Each Plugin contribution can replace
only its complete owned Plugin state entry.

Jido validates both state classes and commits them atomically. Checkpoints
contain both.

Plugin state also uses the Agent portable-term contract. A permissive field
such as `Zoi.any()` cannot admit a PID, port, reference, function, improper
list, or non-byte-aligned bitstring.

If command preparation rejects a Signal or the Turn fails, no Plugin state
changes. A Plugin that must record a rejected attempt must send a separate
Signal or keep non-portable runtime data outside the Agent.

## Bounded callback data

Each preparation callback receives a Command for only that Plugin:

```elixir
%Jido.Plugin.Command{
  source_signal: source_signal,
  signal: effective_signal,
  plugin_id: :scheduler,
  plugin_input: nil
}

%Jido.Plugin.Context{
  plugin_id: :scheduler,
  plugin_module: MyApp.SchedulerPlugin,
  options: %{timezone: "Etc/UTC"},
  agent_id: "counter-1",
  agent_module: MyApp.Counter,
  plugin_state: %{cron: %{}},
  prepared: nil
}
```

It can return a prepared Signal and one owned input value:

```elixir
%Jido.Plugin.Command{
  source_signal: source_signal,
  signal: prepared_signal,
  plugin_id: :scheduler,
  plugin_input: %{timezone: "Etc/UTC"}
}
```

Jido validates `plugin_id`, preserves `source_signal`, and stores the returned
`plugin_input` in a private Map keyed by Plugin ID. A later Plugin sees the
current effective Signal but cannot read or replace another Plugin's input.
After preparation, `Jido.Exec` receives the complete read-only Plugin input Map
as execution context. Each Plugin input must satisfy the portable-term
contract.

After executable evaluation, Jido builds a bounded transition view for each
Plugin:

```elixir
%Jido.Plugin.Transition{
  source_signal_id: "019...",
  signal_id: "019...",
  signal_type: "counter.increment",
  state_before: %{},
  state_after: %{},
  directives: [owned_directive]
}
```

`state_before` and `state_after` contain only the top-level Agent state fields
declared in `plugin.observes`. Jido validates these field names against the
Agent state schema when it constructs the Agent. `directives` contains only
Turn Directives owned by that Plugin ID. It contains no built-in Directive or
Directive owned by another Plugin.

The contribution Context contains the same Plugin configuration and owned
Plugin state as preparation. Its `prepared` field contains only that Plugin's
returned `plugin_input`. A Plugin receives no complete Agent metadata, complete
domain state, or shared preparation Map.

Context validation requires `prepared: nil` during preparation. During
contribution, it requires the exact portable value stored for that Plugin ID.

Contribution returns:

```elixir
%Jido.Plugin.Contribution{
  plugin_state: complete_plugin_state | :unchanged,
  directives: additional_owned_directives
}
```

The Plugin cannot replace its Transition, change domain state, or change the
Turn Directive list. Its contribution can replace only its complete owned
Plugin state and add Directives that it owns.

`directives` in a contribution are additions. A Plugin cannot remove or modify
Directives from executable evaluation. Final Directive order is the Turn
Directive list followed by contributed Directives in Plugin declaration
order.

Before commit, Jido validates each Directive and its declared owner. A Plugin
that needs recovery stores portable intent in its owned state with the business
change. Its supervised worker reads committed state after restart and sends
a completion Signal. Ordinary Directive dispatch has no automatic replay
contract. The [REC-01 example](../examples/rec-01-results.md) proves this path
with the current `update_state/3` API; the broader callback design here remains
a proposal.

`Command`, `Context`, `Transition`, and `Contribution` are Zoi-backed public
structs. They exist because each one crosses a Plugin callback boundary.
Command is the owned preparation input and output. Context is the bounded
capability view. Transition is the declared read projection. Contribution is
the proposed Plugin-owned output.

Plugin Context uses Agent ID and Agent module, not `Agent.Ref`. Direct
`Jido.Agent.cmd/3` has no Jido instance namespace or partition. Runtime-only
callbacks use `Agent.Ref` because they always belong to a live instance.

## Plugin callbacks

The pure command behavior has two callbacks:

```elixir
@callback prepare(Jido.Plugin.Command.t(), Jido.Plugin.Context.t()) ::
            {:ok, Jido.Plugin.Command.t()} | {:error, Jido.Error.t()}

@callback contribute(Jido.Plugin.Transition.t(), Jido.Plugin.Context.t()) ::
            {:ok, Jido.Plugin.Contribution.t()} | {:error, Jido.Error.t()}
```

`use Jido.Plugin` supplies identity implementations. A Plugin overrides only
the callbacks it needs.

The generated defaults are equivalent to:

```elixir
@impl Jido.Plugin
def prepare(%Jido.Plugin.Command{} = command, %Jido.Plugin.Context{}) do
  {:ok, command}
end

@impl Jido.Plugin
def contribute(%Jido.Plugin.Transition{}, %Jido.Plugin.Context{}) do
  {:ok,
   %Jido.Plugin.Contribution{
     plugin_state: :unchanged,
     directives: []
   }}
end
```

`prepare/2` can accept or reject a command, prepare the effective Signal, and
return one owned Plugin input. It can read its owned Plugin state. It cannot
read another Plugin's prepared input, write state, select an executable,
produce an effect, or use a runtime handle.

Jido resolves the executable and route parameters from `source_signal` before
it calls `prepare/2`. A Plugin receives no route-selection handle. Replacing the
effective `signal` changes only the input to the already selected executable.
Jido never runs route selection again during that Turn.

The returned Command must keep the original `source_signal` and its assigned
`plugin_id`. Jido validates these invariants after every preparation callback.

`contribute/2` runs only after successful executable evaluation. It reads only
its declared Transition projection and its own Context. It can replace its
complete owned Plugin state and add owned Directives. It cannot change domain
state, another Plugin's state, or executable output.

Both callbacks are deterministic and free of runtime effects. Exceptions,
throws, exits, invalid return values, and schema failures become structured
Splode errors. The command does not commit.

There is no public `Jido.Plugin.Preparation` or `Jido.Agent.Turn.Result`
struct. `Plugin.Command` is the preparation input and output.
`Plugin.Transition` is the bounded contribution input.

The v3 design does not keep separate Plugin callbacks for state schemas, state
updates, Directive lists, or Directive validation. Static Plugin configuration
declares the schemas and Directive modules. `contribute/2` replaces
`update_state/3`.
Each Directive module owns its Zoi schema, so Jido validates Directives without
a Plugin validation callback.

The v3 design also removes live `admit` and outbound Signal transformation
callbacks. Inbound preparation stays in `prepare/2`. A Plugin runtime that
creates input sends a Signal through the Agent mailbox. Directive dispatch
stays after commit. Capabilities with a process use the runtime behavior; a
capability without a process runs in the Server-owned dispatch task.

Owned `plugin_state` in the Agent is the state source for a Plugin runtime. The
runtime is a disposable projection of that state. Every first start uses
validated initial state at version zero. That state is provisional during
persistent creation before the first Record write. Activation and replacement
use the latest committed complete owned state and Agent state version. A
runtime host never reuses an old Init.

## Plugin composition

Preparation uses an ordered serial reduce for only the effective Signal. Jido
stores each Plugin's returned input in a private keyed Map:

```text
Signal S0 -> Plugin A prepare -> S1 + input A
Signal S1 -> Plugin B prepare -> S2 + input B
Signal S2 -> Plugin C prepare -> S3 + input C
```

Contribution and assembly use one ordered serial reduce. Jido builds a
different bounded Transition for each Plugin:

```text
Transition A + Context A -> Contribution A
Transition B + Context B -> Contribution B
Transition C + Context C -> Contribution C
```

After each callback, Jido validates and applies that complete Plugin state and
its additional owned Directives to a private accumulator. Jido never passes the
accumulator to another Plugin. The first callback or validation error stops the
reduce, discards the candidate, and fails the pre-commit Turn.

Plugin command callbacks run only inside the Turn Evaluator. The Server does
not call them directly. Direct `Jido.Agent.cmd/3` runs the same compiled-Elixir
pipeline to completion. The v3 spike does not run Agent-level Plugin callbacks
concurrently.
