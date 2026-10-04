# 07_06 Plugin Contribution

An Agent Plugin contributes one static Bus, one subscription, and one ownership
relation during Topology planning, so the Topology does not repeat the wiring.

## What you will learn

- How a `Jido.Topology.Plugin` facet returns a pure static contribution.
- How one ownership relation applies to every member of its child group.
- How the common Topology validator checks all contributed entries.
- How an invalid contributed resource stops planning before activation.

## Read the code

Read [the Topology](plugin_contribution.ex), [the Agent](inbox_worker.ex), then
[the Plugin and Topology facet](inbox_plugin.ex).

## Run it

```sh
mix test test/examples/07_topology/07_06_plugin_contribution --include example --seed 0
```

Expected result: planning adds the Bus, subscription, and ownership relation.
The Controller starts the worker and its two owned helpers. A published Signal
changes the worker state. Controller shutdown removes the complete system. A
second Topology contributes an invalid Bus key and cannot be instantiated.

## Important behavior

The source definition stays unchanged. The Plugin contributes one relation to
the `helpers` group declaration. Plan expansion applies it to both members;
the Plugin does not run once per member. Contributions are validated before
activation. Invalid contributions start no Agent or Bus process.

Controller shutdown removes the worker, both helpers, the worker's Plugin
processes, and the contributed Bus.

## Limits

The facet cannot start a process, grant write authority, persist state, or
replace the Controller target.

## Files

- [Topology](plugin_contribution.ex)
- [Agent](inbox_worker.ex)
- [Plugin and facet](inbox_plugin.ex)
- [Tests](../../../test/examples/07_topology/07_06_plugin_contribution/plugin_contribution_test.exs)

Previous: [Composed System](../07_05_composed_system/README.md) | Next: [Lifecycle Signals](../07_07_lifecycle_signals/README.md)
