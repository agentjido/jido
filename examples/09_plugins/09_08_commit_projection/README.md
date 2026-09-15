# Commit projection

The Agent facet copies the domain count into its owned `:projection` field.
The Server facet uses `after_commit/3` to update a live GenServer with that
value and its matching commit revision. The Action returns no Directive and
has no knowledge of the runtime.

The hook runs after every successful Turn commit, including an unchanged
state. `Server.call/3` returns the commit before hook settlement. Hook failure
cannot undo that commit. Agent Server bounds the task and applies its error
policy if the hook fails.

The runtime starts from `Jido.Plugin.Init`. Startup, restore, and runtime
replacement rebuild the current view; they do not replay old notifications.
This is a best-effort live projection, not a durable event stream.

Use semantic Telemetry for observation alone. Use a custom Directive when an
Action must request a specific effect. Use this hook when a Plugin must track
its owned committed state after any successful Turn.

```sh
mix test test/examples/09_plugins/09_08_commit_projection --include example --seed 0
```
