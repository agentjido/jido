# 10_08 Definition Revision

A snapshot retains its definition and state. Code references protect restore
from an unintended change to executable behavior.

Read [the Agent and upgrade Action](definition_revision.ex), then the tests.

```sh
mix test test/examples/10_persistence/10_08_definition_revision --include example --seed 0
```

Expected result: restore retains the saved version even when it differs from
the source definition. A mismatched Action fingerprint rejects restore.
An explicit upgrade Action selects current routes and saves a new snapshot.

The test changes a saved fingerprint to model code from an older release. It
does not replace loaded BEAM code. A snapshot records references to code;
it does not store that code. Keep the required release available, or provide
an upgrade Action. Restore does not select a new definition automatically.

- [Source](definition_revision.ex)
- [Tests](../../../test/examples/10_persistence/10_08_definition_revision/definition_revision_test.exs)
- [Schema and state upgrade](../../04_runtime/04_14_state_migration/README.md)

Previous: [Recoverable Delivery](../10_07_recoverable_delivery/README.md)
