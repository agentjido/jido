# Write a Plugin

Start with [extension selection](extension-boundaries.md#select-an-extension-type).
Use a Plugin when Jido must enforce an Agent rule, such as ownership of a state
field. Use Actions or Flows for reusable work, application supervision for a
shared client or service, and Telemetry for observation.

A small Plugin needs one module and explicit roles:

```elixir
defmodule MyApp.CounterPlugin do
  use Jido.Plugin, roles: [:agent]

  @impl true
  def state_spec(_opts), do: {:turns, Zoi.integer() |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
```

Add `plugin MyApp.CounterPlugin` in the Agent's `agent` block. The Plugin owns
`:turns`. Domain Actions return complete candidate state and must preserve this
field. The reducer computes its next value after executable success. A failed
Turn cannot commit a partial update. This example counts successful Turns; it
does not need a runtime, Persistence callback, or Topology callback.

The roles are `:agent`, `:agent_server`, `:persistence`, and `:topology`.
Jido installs the matching callback behaviours. It rejects callbacks for roles
that the package did not declare. It does not infer roles from helper names.

Use `:agent` for pure prepared input, owned state, and owned Directives. Use
`:agent_server` for live admission or post-commit runtime work. A typed Directive
implements `Jido.Agent.Directive`, and the Agent role declares its type through
`directives/1`. The Server role implements `dispatch/4`. Add `child_spec/1` only
when the capability needs a runtime tied to one Agent's lifetime.

Add `:persistence` only when one owned state value needs format conversion.
Add `:topology` only for static canonical Topology entries. Each role keeps its
own callback contexts and authority, even when the callbacks share a module.

Larger Plugins can keep separate facets, or combine local roles with separate
facets for other owners:

```elixir
use Jido.Plugin,
  roles: [:agent],
  agent_server: MyApp.CounterPlugin.Server,
  vsn: 1,
  option_keys: [agent: [:limit], agent_server: [:endpoint]]
```

Select each owner once. `roles` must be a literal list of unique owners. The
existing `agent: Module` and `agent_server: Module` form remains valid. Both
forms normalize to the same Manifest and owner Specs. Common options,
`option_keys`, package identity, version, and stored declarations keep their
existing meaning.

For a required live view of owned state, declare the Server `after_commit/3`
hook. It receives the exact committed value and revision before Directives.
Failure or timeout skips later hooks and all Directives, then applies the
Server error policy. It cannot undo the state commit or change the commit
result already sent to the caller. Rebuild the view from `Jido.Plugin.Init`
on startup and replacement. Use Telemetry for optional observation.

See `Jido.Plugin.Audit` for a state-only Plugin and `Jido.Plugin.Heartbeat` for
a runtime-only Plugin. The [state middleware example](../examples/09_plugins/09_06_state_middleware/README.md)
and [commit projection example](../examples/09_plugins/09_08_commit_projection/README.md)
show local roles. See [the callback guide](plugin-contract-and-lifecycle.md) for the full contracts.
