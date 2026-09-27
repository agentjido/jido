# Write a Plugin

Start with [extension selection](extension-boundaries.md#select-an-extension-type).
Use a Plugin when Jido must enforce an Agent rule, such as ownership of a state
field. Use Actions or Flows for reusable work, application supervision for a
shared client or service, and Telemetry for observation.

A Plugin needs one module. Implement only the callbacks it needs:

```elixir
defmodule MyApp.CounterPlugin do
  use Jido.Plugin

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

`use Jido.Plugin` installs one behaviour. All callbacks are optional, but a
Plugin must define at least one capability. Jido uses a fixed list of documented
callbacks to select the internal owner Specs. Ordinary helper functions do not
select capabilities. Use `@impl true` to check callback names and arities.

Add callbacks as the Plugin needs more functions:

- `prepare/2` prepares portable input before route selection.
- `admit/3` checks live input or supplies transient runtime input.
- `directives/1` declares owned Directive types. Each type validates itself.
- `dispatch/4` handles owned Directives after commit.
- `child_spec/1` adds a runtime tied to one Agent's lifetime.
- `dump/3` and `load/3` convert one owned state value.
- `contribute/2` supplies static Topology entries.

A reducer needs an owned state field. Persistence needs both conversion
callbacks and an owned state field. Dispatch needs owned Directives. Jido
checks these requirements when it normalizes the Plugin declaration.

A large Plugin can delegate callbacks to ordinary Elixir modules. There is no
second Plugin authoring form. The Plugin module remains the stable identity
used in Agent declarations, diagnostics, and stored definitions.

Pass per-Agent options with `plugin MyApp.CounterPlugin, config: [limit: 100]`.
Each callback receives the same options by default. `vsn` and `option_keys`
remain optional metadata for versioning and restricted owner options. The
Counter above needs neither option.

For a required live view of owned state, define the `after_commit/3`
hook. It receives the exact committed value and revision before Directives.
Failure or timeout skips later hooks and all Directives, then applies the
Server error policy. It cannot undo the state commit or change the commit
result already sent to the caller. Rebuild the view from `Jido.Plugin.Init`
on startup and replacement. Use Telemetry for optional observation.

See `Jido.Plugin.Audit` for a state-only Plugin and `Jido.Plugin.Heartbeat` for
a runtime-only Plugin. The [state middleware example](../examples/09_plugins/09_06_state_middleware/README.md)
and [commit projection example](../examples/09_plugins/09_08_commit_projection/README.md)
use this single authoring form. See [the callback guide](plugin-contract-and-lifecycle.md) for the full contracts.
