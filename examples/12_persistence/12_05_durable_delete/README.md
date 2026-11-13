# 12_05 Durable Delete

A durable tombstone prevents a delayed old writer from recreating a deleted Agent record.

## What you will learn

- How compare-and-swap rejects stale revisions.
- How the local adapter requires the exact stored bytes for replacement.
- Why logical deletion keeps a durable fence.

## Read the code

Read [the order Agent](durable_delete.ex), then read its behavior test.

## Run it

`mix test.examples examples/12_persistence/12_05_durable_delete`

Expected result: load returns `:deleted`, and an old initial writer cannot
replace the tombstone. A byte comparison rejects a condition that is only a
prefix of the stored value.

## Important behavior

Deletion makes the active record unavailable, but it does not remove the
revision barrier. Adapter compare-and-swap checks exact bytes atomically.

## Limits

Tombstone retention and physical purge are application policy. A tombstone is not a cluster ownership lease.

## Files

- [Source](durable_delete.ex)
- [Tests](durable_delete_test.exs)

Previous: [Plugin State Conversion](../12_04_plugin_state_conversion/README.md) | Next: [Indeterminate Write](../12_06_indeterminate_write/README.md)
