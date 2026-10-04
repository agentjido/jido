# 09_08 Commit Projection

A Plugin updates one live view from its exact committed state and revision.

## What you will learn

- How `reduce/2` selects one owned Plugin state value during a Turn.
- How `after_commit/3` receives that value after a successful commit.
- How a replacement runtime restores the latest committed Plugin state.
- Why a live projection is not a durable event stream.

## Read the code

Read [the Agent, Plugin, and runtime](commit_projection.ex). The Action changes
only domain state and returns no Directive. The Plugin owns both the portable
projection value and its supervised live view.

## Run it

```sh
mix test test/examples/09_plugins/09_08_commit_projection --include example --seed 0
```

Expected result: two Turns commit count `5` at revision `2`. After runtime
replacement, the new live view restores `{5, 2}` from the latest commit.

## Important behavior

The runtime starts from `Jido.Plugin.Init`, which pairs the Plugin-owned state
with its commit revision. `after_commit/3` updates the live view after each
successful commit. Runtime replacement reads the latest committed pair. It
does not replay old notifications.

Hook failure and timeout behavior belongs to the Agent Server runtime contract.
The [core after-commit tests](../../../test/jido/plugin/after_commit_test.exs)
cover those detailed failure paths.

## Limits

This projection is a current live view. It is not a durable event stream and
does not retain commit history. Use Agent persistence for durable state and
Telemetry for optional observation.

## Files

- [Source](commit_projection.ex)
- [Tests](../../../test/examples/09_plugins/09_08_commit_projection/commit_projection_test.exs)

Previous: [State Middleware](../09_06_state_middleware/README.md) | Next: [Persistence examples](../../10_persistence/README.md)
