# Plugins

Declare Plugin packages in the Agent definition. Every package uses
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

- `Jido.Agent.Plugin` prepares pure input and reduces one owned state value.
- `Jido.AgentServer.Plugin` handles live admission, one optional permanent
  runtime root, readiness, outbound Signal preparation, and post-commit work.
- `Jido.Persistence.Plugin` converts one paired owned-state value without
  storage or commit authority.
- `Jido.Topology.Plugin` contributes static canonical Topology entries without
  live-control authority.

The bundled Plugins use this same contract. `Audit` has an Agent facet.
`Heartbeat`, `Bus.Client`, and `Bus.Manager` have Server facets. `Dispatch`,
`Scheduler`, and `SensorManager` have both Agent and Server facets. A package
module keeps public constructor helpers, but it does not define lifecycle
callbacks. Put Directive validation on each Directive module.

The Action cannot change protected Plugin keys. After execution, each Agent
facet can read the prior complete state, the current candidate state, its pure
prepared input, and all validated Directives. It returns only the complete next
value for its owned state field. Each custom Directive owns its `validate/1`
callback.

The Agent Server owns all runtime processes and tasks. The optional
`after_commit/3` hook receives the exact owned state and matching revision
after every successful Turn, before returned Directives. A failure skips
remaining work and uses the Server error policy; it cannot undo the commit.
Startup, restore, and runtime replacement use a fresh `Jido.Plugin.Init`
state-version pair instead of replaying notifications.

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
