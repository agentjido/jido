# 07_06 Plugin Contribution

An Agent Plugin contributes one static Bus and one subscription during Topology
planning, so the Topology does not repeat the wiring.

## What you will learn

- How a `Jido.Topology.Plugin` facet returns a pure static contribution.
- How the common Topology validator checks contributed resources and connections.

## Read the code

Read [the Topology](plugin_contribution.ex), [the Agent](inbox_worker.ex), then
[the Plugin and Topology facet](inbox_plugin.ex).

## Run it

```sh
mix test test/examples/07_topology/07_06_plugin_contribution --include example --seed 0
```

Expected result: planning adds the Bus and subscription, the Controller starts
them, and a published Signal changes the worker state.

## Important behavior

The source definition stays unchanged. Contributions are applied during
instantiation and validated before activation.

## Limits

The facet cannot start a process, grant write authority, persist state, or
replace the Controller target.

## Files

- [Topology](plugin_contribution.ex)
- [Agent](inbox_worker.ex)
- [Plugin and facet](inbox_plugin.ex)
- [Tests](../../../test/examples/07_topology/07_06_plugin_contribution/plugin_contribution_test.exs)

Previous: [Composed System](../07_05_composed_system/README.md) | Next: [Lifecycle Signals](../07_07_lifecycle_signals/README.md)
