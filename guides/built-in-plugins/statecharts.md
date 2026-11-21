# Statecharts

Use SCXML to define which states an Agent can enter and which Signals can
change its state. `Jido.Statechart` compiles the chart.
`Jido.Plugin.Statechart` runs it and keeps the committed session on the Agent.

## Start an Agent from a chart

Define a chart with `~SCXML` to compile it with the module.

```elixir
defmodule Orders.Approval do
  use Jido.Statechart,
    chart: ~SCXML"""
    <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="pending">
      <state id="pending">
        <transition event="order.approved" target="approved"/>
      </state>
      <final id="approved"/>
    </scxml>
    """
end
```

Start a chart Agent in a running Jido instance. `spawn/3` waits for
initialization to commit before it returns the PID.

```elixir
{:ok, order} = Jido.Statechart.spawn(MyApp.Jido, Orders.Approval, id: "order-42")

signal = Jido.Signal.new!("order.approved", %{}, source: "/orders")
{:ok, %{status: :committed}} = Jido.AgentServer.call(order, signal)
%{state: "approved", status: :completed} = Jido.Statechart.session(order)

:ok = Jido.stop_agent(MyApp.Jido, order)
```

For XML loaded at runtime, call `Jido.Statechart.compile/1`. It returns
`{:ok, chart}` or `{:error, %Jido.Statechart.Error.InvalidChart{}}`. You can pass
the compiled value to `spawn/3`.

## Add a chart to an Agent

Use the Plugin when the Agent also has application state, Flows, or other
Plugins. Add a route for each application event that the chart receives.

```elixir
defmodule Orders.ApprovalAgent do
  use Jido.Agent,
    name: "order_approval",
    plugins: [{Jido.Plugin.Statechart, %{chart: Orders.Approval}}]

  routes do
    route "order.approved", Jido.Plugin.Statechart.Route, as: :approve
  end
end
```

Start the Agent with `Jido.start_agent/3`. Call
`Jido.Statechart.initialize/1` and check for `{:ok, %{status: :committed}}`
before sending chart events. Pass a map to `initialize/2` to supply values for
declared root data. `session/1` returns `nil` before initialization.

Give the chart a `registry:` to bind names to trusted guards, Actions, or
child Agent modules. For a named guard, use a map such as
`%{guards: %{"checks_passed" => {MyApp.Guards, :checks_passed?}}}`. The guard
receives a map with `:data` and `:event` and returns a boolean.

## Execution and support

The chart supports compound and parallel states, shallow and deep history,
final states, eventless transitions, and named event descriptors. The
compiler supports the null and Jido data models. ECMAScript and script
elements are outside the supported subset.

A Flow runs up to 100 microsteps to reach a stable configuration. If the
chart exceeds this limit, the Turn fails and the prior session stays in
place. AgentServer commits the session before the Plugin runs external
effects such as HTTP sends and child Agent invocations.

To receive Basic HTTP events, supply an `:http_location` when you start or
initialize the chart. In your HTTP endpoint, pass the POST body and content
type to `Jido.Statechart.BasicHTTP.receive_post/3`. The application owns the
listener and access control. Provide chart XML from a trusted source when
the chart can send HTTP requests or invoke registered code.

## Move from the separate package

Remove `:jido_statechart` when you upgrade to a Jido version that includes
Statechart. Change `Jido.Statechart.Plugin` to `Jido.Plugin.Statechart` in
Plugin declarations and route targets. Keep `use Jido.Statechart` in chart
modules. Rebuild saved Agent definitions that refer to the old Plugin ID or
route module.

## Run the W3C tests

From the Jido repository root, run:

```sh
mix test test/jido/plugin/statechart/w3c_test.exs --include scxml_conformance --warnings-as-errors
```

ExUnit reads the full fixture manifest. It skips scripting and ECMAScript
cases and uses a loopback listener for HTTP cases. Test support translates
fixtures in memory. Fixture 198 checks the translated `origintype` comparison.
Fixture 352 expects the event processor URI and has a test for its known
failure. The runtime reports `"scxml"`.

See the [standalone approval example](https://github.com/agentjido/jido/blob/main/examples/11_built_in_capabilities/11_07_statechart_approval/README.md)
and the [Agent Plugin example](https://github.com/agentjido/jido/blob/main/examples/11_built_in_capabilities/11_08_statechart_plugin/README.md).
