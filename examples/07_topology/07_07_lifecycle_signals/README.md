# 07_07 Lifecycle Signals

A Topology module can define an optional control Agent and an optional topology.
The two blocks are independent. A `routes` block requires the `agent` block and
uses the normal Agent route syntax.

## What you will learn

- How `agent` and `routes` define the control Agent.
- How `topology` defines the system that the Controller starts.
- How the Controller sends lifecycle Signals to the control Agent.
- How each lifecycle event uses a custom `Jido.Signal` module.
- How control policy stays in normal Agent routes.

## Read the code

Read [the combined definition](lifecycle_signals.ex). The root `routes` block
handles `jido.topology.lifecycle.**`. Topology declarations stay under
`topology do`. The event modules are
`Jido.Topology.Signal.OperationStarted`,
`Jido.Topology.Signal.OperationCompleted`,
`Jido.Topology.Signal.ComponentReady`,
`Jido.Topology.Signal.ComponentFailed`, and
`Jido.Topology.Signal.StatusChanged`.

## Run it

```sh
mix test test/examples/07_topology/07_07_lifecycle_signals --include example --seed 0
```

The application starts the control Agent first. It then gives that Agent to the
Controller through the `:lifecycle` option. Lifecycle delivery is best effort.
It does not change activation or repair results.

Previous: [Plugin Contribution](../07_06_plugin_contribution/README.md) | Next: [Placement Policy](../07_08_placement_policy/README.md)
