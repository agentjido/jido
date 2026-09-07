# Signals, Commands, and Routes

A Signal is a typed message. An Agent command combines one Agent instance, one
Signal, and caller context. Routing selects exactly one Action or Flow for the
effective Signal.

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
context map. Plugins can prepare the Signal or context before route selection.
They cannot replace the Agent.

The live Server adds these reserved context keys for execution:

- `:agent_id`
- `:agent_state`
- `:signal`
- `:jido`
- `:partition`

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

## Require One Target

Route patterns can use Jido Signal Router patterns and match predicates. A
command must have exactly one matching target. No match and multiple matches
return `Jido.Error.RoutingError` before executable work starts.

An exact route does not silently override a matching wildcard route. Test all
overlapping patterns. Plugin preparation can change the Signal type before
route selection, so policy must use the effective Signal.

## Generate Interfaces

An exact DSL route can declare `define`. Jido then creates constructors such as
`add_signal/1` and live helpers such as `add/3`. A generated interface cannot
use a wildcard route or a route match predicate.

See [Route Interfaces](route-interfaces.livemd) and
[Use Jido Signal](jido-signal-messaging.md).
