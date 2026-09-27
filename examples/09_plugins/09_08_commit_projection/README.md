# 09_08 Commit projection

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
The package implements `roles: [:agent, :agent_server]` in one module.
Its declared hook is a required step before Directive dispatch. Failure or
timeout skips later hooks and Directives and uses the Server error policy.
The commit and the result already sent to the caller remain unchanged.
This view is not a durable event stream. Use Telemetry for optional observation.

Use semantic Telemetry for observation alone. Use a custom Directive when an
Action must request a specific effect. Use this hook when a Plugin must track
its owned committed state after any successful Turn.

Read [the Agent and Plugin source](commit_projection.ex) first, then
[the test](../../../test/examples/09_plugins/09_08_commit_projection/commit_projection_test.exs).
Build the command with `Agent.add_signal(%{amount: amount})`. Pass the Signal to
`Jido.AgentServer.call/3` to change the count.

```sh
mix test test/examples/09_plugins/09_08_commit_projection --include example --seed 0
```

Expected result: the domain count and live projection both become `3`, at
revision `1`. Stopping the Server also stops the projection runtime.

Previous: [Persisted State](../09_07_persisted_state/README.md).
