# Plugins

Declare Plugin packages in the Agent definition. Every package uses
`Jido.Plugin` with explicit local roles or separate owner facets. Start with
[extension selection](extension-boundaries.md#select-an-extension-type) and
[Write a Plugin](your-first-plugin.md). A separate-facet declaration is:

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

The bundled Plugins use this same contract. `Audit` implements `roles: [:agent]`
in its package module.
`Heartbeat` implements `roles: [:agent_server]`. `Bus.Client` and `Bus.Manager`
use separate Server facets. `Scheduler` and `SensorManager` have both Agent
and Server facets. A package module can keep public constructor helpers and
callbacks for its declared local roles. Put Directive validation on each
Directive module.

The Action cannot change protected Plugin keys. After execution, each Agent
facet can read the prior complete state, the current candidate state, its pure
prepared input, and all validated Directives. It returns only the complete next
value for its owned state field. Each custom Directive owns its `validate/1`
callback.

The Agent Server owns all runtime processes and tasks. A declared
`after_commit/3` hook receives the exact owned state and matching revision
after every successful Turn, before returned Directives. It is a required step
before dispatch. Failure or timeout skips later hooks and Directives and uses
the Server error policy. It cannot undo the commit or
change the result already sent to the caller. Use Telemetry for observation.
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
