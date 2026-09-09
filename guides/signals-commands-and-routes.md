# Signals, Commands, and Routes

A Signal is a typed message. An Agent command combines one Agent instance, one
Signal, and caller context. Routing selects the first Action or Flow for the
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

## Prepare A Command

`Jido.Agent.Command` carries the current Agent, the Signal, and a caller-owned
context map. Jido selects a Turn before Plugins prepare the effective Signal or
context. Plugins cannot replace the selected executable or the Agent.

The live Server adds these reserved context keys for execution:

- `:agent_id`
- `:agent_state`
- `:signal`
- `:plugin_inputs`
- `:jido`
- `:partition`

`plugin_inputs` is keyed by Plugin package module. Each value belongs to that
package. It is read-only execution context.

Caller context is not stored or copied into emitted Signals. Application code
must select any value that must enter state or a new Signal.

## Apply Route Defaults

A route can pair an executable with a defaults map:

```elixir
routes: [
  {"counter.add", {MyApp.Add, %{amount: 1}}}
]
```

Signal data replaces matching default keys. The merge is shallow. A supplied
nested map replaces the complete nested default map. Invalid supplied values do
not fall back to defaults.

Default routing requires map-shaped Signal data. The Signal in execution
context keeps its original data.

## Use The First Target

Route patterns can use Jido Signal Router patterns and match predicates. A
command uses the first matching target in Router order. No match returns
`Jido.Error.RoutingError` before executable work starts.

Router priority and specificity put an exact route before matching wildcard
routes. Test all overlapping patterns. Plugin preparation can change the
effective Signal after selection, but it cannot select a different executable.

## Generate Interfaces

An exact DSL route can declare `define`. Jido then creates constructors such as
`add_signal/1` and live helpers such as `add/3`. A generated interface cannot
use a wildcard route or a route match predicate.

See [Route Interfaces](route-interfaces.livemd) and
[Use Jido Signal](jido-signal-messaging.md).
