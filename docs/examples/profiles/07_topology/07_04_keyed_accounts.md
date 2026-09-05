# Keyed Account Agents

Feature ID: `07_04_keyed_accounts`. Status: implemented within the topology spike scope.

Account records supply stable group member keys and initial labels. Reordering the records does not change Agent identity.

[Source](../../../../lib/examples/07_topology/07_04_keyed_accounts/accounts.ex) ·
[Guide](../../../../lib/examples/07_topology/README.md) ·
[Tests](../../../../test/examples/07_topology/07_04_keyed_accounts)

The spike supports local eager activation and periodic repair. It does not
provide cluster placement or a database adapter.
