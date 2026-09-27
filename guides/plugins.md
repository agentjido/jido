# Plugins

Declare Plugins in the Agent definition. Each Plugin uses one `Jido.Plugin`
module with optional callbacks. Start with
[extension selection](extension-boundaries.md#select-an-extension-type) and
[Write a Plugin](your-first-plugin.md).

```elixir
defmodule MyApp.Counter do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:turns, Zoi.integer() |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
```

Implement only the documented callbacks that the Plugin needs. No role list or
facet modules are required. Core enforces each callback's limits:

- Agent prepares portable input and reduces one owned state value.
- Agent Server handles live admission, an optional runtime root, readiness,
  outbound Signal preparation, and work after commit.
- Persistence converts one owned value without storage or commit authority.
- Topology contributes static entries without live control authority.

The bundled Plugins use this same contract. `Audit` owns and reduces state.
`Heartbeat`, `Bus.Client`, and `Bus.Manager` supply runtime callbacks.
`Scheduler` and `SensorManager` combine state and runtime callbacks. Large
Plugins can delegate work to ordinary helper modules. Put Directive validation
on each Directive module.

The Action cannot change protected Plugin keys. After execution, each reducer
can read the prior complete state, the current candidate state, its pure
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

Persistence runs conversion callbacks only for the default Agent
checkpoint. It gives each callback one paired owned-state value, bounded format
context, and mapped static options. A complete custom Agent checkpoint bypasses
this conversion. Topology contribution is a pure callback and does not
give the Plugin live-control authority. Instance planning applies Topology
contributions in stable Agent, group, and Plugin declaration order. It validates
the combined graph before activation and keeps generated entries out of the
source definition.

See [Plugin Contract and Lifecycle](plugin-contract-and-lifecycle.md),
[Plugin-Owned State](plugin-state.md), and
[Plugin Runtimes](plugin-runtimes.livemd). See
[Topology Definitions](topology-definitions.md) for static contribution use.
