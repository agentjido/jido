# 10_08 Definition Revision

Persistence rejects a checkpoint when the same Agent module has a different declared definition revision.

## What you will learn

- How a matching definition restores the complete saved state.
- How a changed `vsn` blocks an unsafe restore.

## Read the code

Read [the isolated revision installer](definition_revision.ex), then read its behavior test.

## Run it

`mix test test/examples/10_persistence/10_08_definition_revision --include example --seed 0`

Expected result: revision 1 restores and revision 2 returns a definition mismatch before startup.

## Important behavior

Schema compatibility is not enough. A changed definition revision requires an explicit migration decision.

## Limits

This serial example reloads one isolated module. It does not perform automatic state migration.

## Files

- [Source](definition_revision.ex)
- [Tests](../../../test/examples/10_persistence/10_08_definition_revision/definition_revision_test.exs)

Previous: [Recoverable Delivery](../10_07_recoverable_delivery/README.md)
