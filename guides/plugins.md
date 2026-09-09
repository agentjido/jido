# Plugins

Declare Plugin packages in the Agent definition. A new package uses
`Jido.Plugin` only as a manifest:

```elixir
defmodule MyApp.Capability do
  use Jido.Plugin,
    agent: MyApp.Capability.Agent,
    agent_server: MyApp.Capability.Server,
    persistence: MyApp.Capability.Persistence,
    topology: MyApp.Capability.Topology,
    vsn: 1
end
```

Select only the facets that the package needs. Each facet has one owner and one
bounded authority:

- `Jido.Agent.Plugin` prepares Turn input and contributes owned state and
  Directives.
- `Jido.AgentServer.Plugin` handles live admission, one optional permanent
  runtime root, readiness, outbound Signal preparation, and post-commit work.
- `Jido.Persistence.Plugin` converts one paired owned-state value without
  storage or commit authority.
- `Jido.Topology.Plugin` contributes static canonical Topology entries without
  live-control authority.

The Action cannot change protected Plugin keys. Each Agent facet receives only
its declared domain projection and its owned state and input. The selected
executable reads package inputs from `context.plugin_inputs`.

The Agent Server owns all runtime processes and tasks. It runs Directive work
after commit. A failed dispatch does not undo the commit. Supplying committed
state and its matching version directly in replacement Init belongs to the
Agent Server alignment work.

`use Jido.Plugin` with no options keeps the mixed compatibility behavior for
current built-ins. New packages should use owner facets.

See [Plugin Contract and Lifecycle](plugin-contract-and-lifecycle.md),
[Plugin-Owned State](plugin-state.md), and
[Plugin Runtimes](plugin-runtimes.livemd).
