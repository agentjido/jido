# 04_13 Turn Upgrade

An explicit upgrade operation waits for active Turn and Directive work to stop.

## What you will learn

- How `AgentServer.upgrade/3` gives a release installer a serialized idle boundary.
- How the same Agent process handles later work after the installer succeeds.

## Read the code

Read [the Agent and release boundary](turn_upgrade.ex). Then read the behavior
test. Its blocking Action is test-only support for an active Turn.

## Run it

```sh
mix test test/examples/04_runtime/04_13_turn_upgrade --include example --seed 0
```

Expected result: active work observes the old release marker. The installer runs
only after that Turn commits. The next Turn observes the new marker on the same
Agent process.

## Important behavior

Pass a callback that invokes your OTP release or deployment installer. Jido
serializes that callback with Agent work. It does not load, pin, purge, or
distribute BEAM modules for you.

## Limits

This example uses a deterministic marker instead of compiling code at runtime.
It does not coordinate several nodes or replace an OTP release procedure.

## Files

- [Source](turn_upgrade.ex)
- [Tests](../../../test/examples/04_runtime/04_13_turn_upgrade/turn_upgrade_test.exs)

Previous: [Stable Reference](../04_12_stable_reference/README.md) | Next: [State Migration](../04_14_state_migration/README.md)
