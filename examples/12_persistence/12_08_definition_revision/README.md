# 12_08 Definition Revision

A snapshot retains its definition and state. Code references protect restore
from an unintended change to executable behavior.

Read [the Agent and upgrade Action](definition_revision.ex), then the tests.

```sh
mix test.examples examples/12_persistence/12_08_definition_revision
```

Expected result: restore retains the saved version even when it differs from
the source definition. A mismatched Action fingerprint rejects restore.
An explicit upgrade Action selects current routes and saves a new snapshot.

The test changes a saved fingerprint to model code from an older release. It
does not replace loaded BEAM code. A snapshot records references to code;
it does not store that code. Keep the required release available, or provide
an upgrade Action. Restore does not select a new definition automatically.

- [Source](definition_revision.ex)
- [Tests](definition_revision_test.exs)
- [Schema and state upgrade](../12_09_state_migration/README.md)

A nested definition is captured as data rather than reselected from current
source on restore. Topology intent includes members, their initial inputs,
counts, and connections. It does not include a coordinated live snapshot of
all running members. Use a whole-definition upgrade to change this data for a
running activation.

Previous: [Recoverable Delivery](../12_07_recoverable_delivery/README.md) |
Next: [Durable Agents](../../13_durable_execution/README.md)
