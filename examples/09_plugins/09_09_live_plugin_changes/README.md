# 09_09 Live Plugin Changes

An Agent installs, reconfigures, and removes a state-owning runtime Plugin.

## What you will learn

- How `plugin_add`, `plugin_configure`, and `plugin_remove` change contributions.
- Why live replacement needs idempotent `quiesce/2` and `resume/2`.
- Why removing owned state requires an explicit discard decision.

## Read the code

Read [the Agent](live_plugin_changes.ex), then [the behavior tests](../../../test/examples/09_plugins/09_09_live_plugin_changes/live_plugin_changes_test.exs).
Read [the Plugin and its revision cache](cache.ex) next. Tests inspect the owned runtime through [OTP test assertions](../../../test/support/agent_server_assertions.ex).

## Run it

```sh
mix test test/examples/09_plugins/09_09_live_plugin_changes --include example --seed 0
```

Expected result: installation starts the Plugin from revision one. Configuration replaces the runtime while retaining its owned value. Invalid capacity and removal without a state decision preserve the accepted Agent. Explicit removal stops the runtime and discards its owned field.

## Important behavior and limits

The Plugin validates its options before runtime startup. Quiescence pauses
old resources before the configuration commits. Resume reopens old resources
when a pre-commit change is rejected or cancelled. Both callbacks must be
idempotent. The old runtime remains paused through save; the replacement
starts from `Jido.Plugin.Init` with the accepted state and revision.

New, removed, and reconfigured Plugins do not receive `after_commit/3` for that
configuration commit. An unchanged Plugin receives its normal notification.
Hooks are not replayed on restore. Wait for `Server.await_ready/1` before using
replaced resources.

The revision cache is transient local runtime state. This lesson does not
provide an external cache service, distributed invalidation, or durable effects.
Detailed fault and cancellation barriers remain in core tests.

Previous: [Composition](../09_05_composition/README.md) | Next: [Identity](../09_03_identity/README.md)

The File persistence test changes Plugin options, commits owned state, then
hibernates and thaws the Agent. Thaw uses the saved capacity, owned value, and
revision to rebuild the runtime. It does not replay `after_commit/3`. A runtime
must be able to start from `Jido.Plugin.Init` alone.
