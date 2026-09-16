# 99_13 Durable Delete

Status: implemented persistence contract; lesson in the
[Persistence guide](../../../guides/storage.md#keep-the-delete-fence).

A durable tombstone prevents a delayed old writer from recreating a deleted
Agent record.

## What this proves

- Compare-and-swap rejects stale revisions before deletion.
- The deletion fence remains after the record becomes unavailable to load.

## Read the code

Read [the order Agent and delayed write helper](durable_delete.ex).

## Run it

```sh
mix test test/examples/99_research/99_13_durable_delete --include example --seed 0
```

Expected result: deletion returns `:deleted`, and an old initial writer cannot
replace the tombstone.

## Gap and limits

The fence exists. The stable guide places deletion beside persistence
lifecycle and compare-and-swap. Tombstone retention and physical purge remain
application policy.

## Files

- [Source](durable_delete.ex)
- [Tests](../../../test/examples/99_research/99_13_durable_delete/durable_delete_test.exs)

Previous: [Definition Revision](../99_12_definition_revision/README.md) | Next: [Turn Upgrade](../99_14_turn_upgrade/README.md)
