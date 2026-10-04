# 10_04 Plugin State Conversion

A Plugin converts only its owned state field to and from a portable stored form.

## What you will learn

- How `dump/3` and `load/3` convert Plugin-owned state.
- How malformed or missing stored Plugin state blocks Agent startup.

## Read the code

Read [the Agent](persisted_state.ex), then [the Plugin callbacks](persisted_state_plugin.ex), and then the behavior test.

## Run it

`mix test test/examples/10_persistence/10_04_plugin_state_conversion --include example --seed 0`

Expected result: the Plugin-owned integer is stored as a string and restores as an integer. An invalid stored value does not start an Agent.

## Important behavior

Each callback receives only its paired Plugin value. It cannot change the complete Agent state, record revision, or adapter.

## Limits

The example uses a small string format. It does not define a schema migration policy.

## Files

- [Agent](persisted_state.ex)
- [Plugin callbacks](persisted_state_plugin.ex)
- [Tests](../../../test/examples/10_persistence/10_04_plugin_state_conversion/persisted_state_test.exs)

Previous: [Portable Checkpoint](../10_03_portable_checkpoint/README.md) | Next: [Durable Delete](../10_05_durable_delete/README.md)
