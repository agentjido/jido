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

## Prepare A Command

`Jido.Agent.Command` is the live Agent Server admission envelope. It carries
the current Agent, the unchanged Signal, a caller-owned context map, and a
package-keyed `plugin_inputs` map. Direct `Jido.Agent.cmd/3` evaluation does not
create this envelope.

Before route selection, a pure Agent Plugin can reject the command or return
one portable value under its package key. A live Agent Server Plugin can reject
the command or replace only its own package value. Neither callback can change
the Signal, caller context, selected executable, Agent, or another package's
input. Jido then selects one Turn from the unchanged Signal.

The live Server adds these reserved context keys for execution:

- `:agent_id`
- `:agent_state`
- `:plugin_inputs`
- `:signal`
- `:jido`
- `:partition`

Caller context is not stored or copied into emitted Signals. Application code
must select any value that must enter state or a new Signal.

`Jido.Agent.cmd/3` runs pure Agent Plugin preparation. It does not run live
admission or use Plugin runtimes. Therefore, a pure signature check can work in
direct evaluation, but replay claims and private-key decryption stay at the
live Agent Server boundary.

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
routes. Test all overlapping patterns.

## Generate Interfaces

An exact DSL route can declare `define`. Jido then creates constructors such as
`add_signal/1` and live helpers such as `add/3`. A generated interface cannot
use a wildcard route or a route match predicate.

See [Route Interfaces](route-interfaces.livemd) and
[Use Jido Signal](jido-signal-messaging.md).
