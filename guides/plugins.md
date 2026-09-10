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

- `Jido.Agent.Plugin` validates owned Directives and updates one owned state
  value.
- `Jido.AgentServer.Plugin` handles live admission, one optional permanent
  runtime root, readiness, outbound Signal preparation, and post-commit work.
- `Jido.Persistence.Plugin` converts one paired owned-state value without
  storage or commit authority.
- `Jido.Topology.Plugin` contributes static canonical Topology entries without
  live-control authority.

The Action cannot change protected Plugin keys. After execution, each Agent
facet receives its current owned state and only its owned Directives. It
returns the complete next owned state.

The Agent Server owns all runtime processes and tasks. It runs Directive work
after commit. A failed dispatch does not undo the commit. Supplying committed
state and its matching version directly in replacement Init belongs to the
Agent Server alignment work.

Persistence runs a selected Persistence facet only for the default Agent
checkpoint. It gives the facet one paired owned-state value, bounded format
context, and mapped static options. A complete custom Agent checkpoint bypasses
this conversion. Topology contribution is a separate pure facet and does not
give the Plugin live-control authority. Instance planning applies Topology
contributions in stable Agent, group, and Plugin declaration order. It validates
the combined graph before activation and keeps generated entries out of the
source definition.

See [Plugin Contract and Lifecycle](plugin-contract-and-lifecycle.md),
[Plugin-Owned State](plugin-state.md), and
[Plugin Runtimes](plugin-runtimes.livemd). See
[Topology Definitions](topology-definitions.md) for static contribution use.
