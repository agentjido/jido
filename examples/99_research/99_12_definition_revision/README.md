# 99_12 Definition Revision

Status: implemented restore contract; awaiting stable migration guidance.

Persistence rejects a checkpoint when the same Agent module has a different
declared definition revision.

## What this proves

- A matching definition restores the complete saved state.
- A new revision is rejected even when the saved state still passes its schema.

## Read the code

Read [the isolated revision installer](definition_revision.ex).

## Run it

```sh
mix test test/examples/99_research/99_12_definition_revision --include example --seed 0
```

Expected result: revision 1 restores and revision 2 returns a definition
mismatch before restore.

## Gap and limits

The restore guard exists. Promotion should explain how it relates to explicit
state migration. This serial probe reloads one isolated module and does not
perform automatic migration.

## Files

- [Source](definition_revision.ex)
- [Tests](../../../test/examples/99_research/99_12_definition_revision/definition_revision_test.exs)

Previous: [Stable Reference](../99_11_stable_reference/README.md) | Next: [Durable Delete](../99_13_durable_delete/README.md)
