# 09_07 Persisted State

A Persistence facet stores one Plugin-owned value in a different portable form.

## What you will learn

- How an Agent facet owns one state field and a paired Persistence facet converts only that field.
- How a malformed or missing stored field stops restore before an Agent starts.

## Read the code

Read [the Agent](persisted_state.ex), then [the Plugin facets](persisted_state_plugin.ex),
then the behavior test.

## Run it

```sh
mix test test/examples/09_plugins/09_07_persisted_state --include example --seed 0
```

Expected result: `visible` remains an integer in the stored checkpoint. The
Plugin-owned `owned` value is stored as a string and restores as an integer.
An invalid stored value returns an error and does not restore the Agent.

## Important behavior

The Persistence facet receives only its paired Plugin-owned value. It cannot
read or change the complete Agent state, record revision, or storage adapter.

## Limits

This example uses local ETS storage and a simple string format. It does not
provide schema migration or a durable storage service.

## Files

- [Agent](persisted_state.ex)
- [Plugin facets](persisted_state_plugin.ex)
- [Tests](../../../test/examples/09_plugins/09_07_persisted_state/persisted_state_test.exs)

Previous: [State Middleware](../09_06_state_middleware/README.md)
