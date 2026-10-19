# Signals, Commands, and Routes

A Signal is a typed message. Direct evaluation accepts one Agent instance, one
Signal, and caller context. Live Agent Server admission stores these values in
a `Jido.Agent.Command`. Routing selects the first Action or Flow for the
unchanged source Signal.

Signal construction, transport, and dispatch come from
[Jido Signal](https://hexdocs.pm/jido_signal/).

## Create A Signal

```elixir
{:ok, signal} =
  Jido.Signal.new(%{
    type: "counter.add",
    source: "/orders/checkout",
    data: %{amount: 2}
  })
```

Use `type` for stable event meaning. Use `source` to identify the producing
part of the application. A Signal ID identifies the message. It does not prove
that a business request is unique.

## Define A Signal And Action Together

Use `Jido.SignalAction` to share one input schema between a Signal and an Action.
Keep the normal `run/2` callback:

```elixir
defmodule MyApp.CreateThread do
  use Jido.SignalAction,
    name: "create_thread",
    description: "Create a named chat thread",
    vsn: 1,
    input: [type: "chat.thread.create", schema: Zoi.object(%{name: Zoi.string()})],
    output: [type: "chat.thread.created", schema: Zoi.object(%{id: Zoi.string()})]

  @impl Jido.Action
  def run(data, %{client: client}), do: MyApp.Threads.create(client, data)
end

{:ok, request} = MyApp.CreateThread.new(%{name: "General"}, source: "/caller")
{:ok, data} = Jido.Exec.run(MyApp.CreateThread, request.data, %{client: client})
{:ok, reply} = MyApp.CreateThread.reply(request, data, source: "/chat")
```

The input schema checks Signal data and Action parameters. The output schema
checks Action results and reply data. The Signal envelope has its own schema.
Each definition uses the full Signal type string. The keyword options also accept
`dataschema:` for a schema URI. Tuple forms are not supported.
`reply/3` builds `chat.thread.created` with a new ID. It keeps the
request trace and sets the causation ID to the request ID. It does not dispatch
the reply. Errors use the normal Action error contract.

A module route uses the declared input type. `route MyApp.CreateThread` selects
that Action and keeps the normal complete Agent state contract. For domain work
that must run after commit, select a handler that returns a Plugin Directive:

```elixir
routes do
  route MyApp.CreateThread, via: MyApp.ExecuteAfterCommit
end
```

This expands to `route "chat.thread.create", MyApp.ExecuteAfterCommit`. The
handler and its Plugin keep control of execution after commit.

## Prepare A Command

`Jido.Agent.Command` is the live Agent Server admission envelope. It carries
the current Agent, the unchanged Signal, a caller-owned context map, and a
package-keyed `plugin_inputs` map. Direct `Jido.Agent.cmd/3` evaluation does not
create this envelope.

Before route selection, a pure Agent Plugin can reject the command or return
one portable value in its package `prepared` slot. A live Agent Server Plugin
receives a read-only admission value. It can reject the command or return one
transient value for its package `runtime` slot. Neither callback can change the
Signal, caller context, selected executable, Agent, prepared input, or another
package's input. Jido then selects one Turn from the unchanged Signal.

An Action or Flow reads these separate values as
`context.plugin_inputs[Package].prepared` and
`context.plugin_inputs[Package].runtime`.

The live Server adds these reserved context keys for execution:

- `:agent_id`
- `:agent_state`
- `:plugin_inputs`
- `:signal`
- `:jido`
- `:partition`

Caller context does not become Agent state or emitted Signal data. A persistent
Flow saves portable caller context for recovery. Application code must select
values that enter state or a new Signal.

`Jido.Agent.cmd/3` runs pure Agent Plugin preparation. It does not run live
admission or use Plugin runtimes. Therefore, a pure signature check can work in
direct evaluation, but replay claims and private-key decryption stay at the
live Agent Server boundary.

## Apply Route Defaults

A route can pair an executable with a defaults map:

```elixir
routes do
  route "counter.add", MyApp.Add, defaults: %{amount: 1}
end
```

Signal data replaces matching default keys. The merge is shallow. A supplied
nested map replaces the complete nested default map. Invalid supplied values do
not fall back to defaults.

Default routing accepts maps, keyword lists, and `nil`. A keyword list becomes
a map; the last value for a duplicate key wins. `nil`, `[]`, and `%{}` use all
route defaults. Other data returns a validation error. The Signal in execution
context keeps its original data. Route defaults must be a plain map.

## Use The First Target

Route patterns can use Jido Signal Router patterns and match predicates. A
command uses the first matching target in Router order. No match returns
`Jido.Error.RoutingError` before executable work starts.

Declaration order sets precedence. Put a specific route before a matching
wildcard route. Routes have no priority option. Test overlapping patterns.

## Use Agent State In An Action

Declare routes to select Actions or Flows. Put decisions that need current
Agent state in the selected Action or Flow. An Action reads that state from
`context.agent_state`.

## Generate Interfaces

An exact DSL route can set `as: :add`. Jido then creates `add_signal/1,2`,
which accepts an input map and optional envelope options. Each route can name
one helper. Omit `as:` to generate no helper. A generated interface cannot
use a wildcard route or a route match predicate.

See [Route Interfaces](route-interfaces.livemd) and
[Use Jido Signal](jido-signal-messaging.md).
