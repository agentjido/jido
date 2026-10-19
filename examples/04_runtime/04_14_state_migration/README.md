# 04_14 State Migration

One snapshot upgrade Action changes a wallet schema, version, and state together.
The Agent ID and origin module stay the same.

## Read the code

[StateMigration](state_migration.ex) defines a version 1 wallet and one named
Action, `WalletV1ToV2`. The Action receives `%{snapshot: snapshot}` and returns
`{:ok, %{snapshot: upgraded_snapshot}}`. It also accepts version 2 snapshots.

## Run it

```sh
mix test test/examples/04_runtime/04_14_state_migration --include example --seed 0
```

```elixir
alias Jido.AgentServer, as: Server
alias Jido.Examples.StateMigration
alias Jido.Examples.StateMigration.WalletV1ToV2
alias Jido.Persistence

{:ok, server} = Jido.start_agent(MyJido, StateMigration)
:ok = Server.await_ready(server)
before = Server.snapshot(server)
{:ok, upgraded, []} = Server.upgrade(server, WalletV1ToV2)

{:ok, saved} = Persistence.snapshot(before.agent)
{:ok, upgraded_offline} = Persistence.upgrade(saved, WalletV1ToV2)
{:ok, saved_upgrade} = Persistence.snapshot(upgraded_offline)
{:ok, restored} = Persistence.restore(saved_upgrade)
```

Expected state: `%{wallet: %{format: 2, amount: 100, currency: "USD"}}`.
Invalid target data leaves the live Agent and its revision unchanged.

## Behavior and limits

`Server.snapshot/1` returns the accepted Agent and its runtime revision.
`Persistence.snapshot/1` captures a portable definition and state.
`Persistence.restore/1` restores that saved definition. It does not rebuild the
Agent from the current source definition or run an upgrade automatically.

The Action has no external effects and returns no directives. A repeated upgrade
preserves the version 2 data. Each successful live upgrade can advance the
runtime revision. This example does not coordinate upgrades across Agents.

## Files

- [Source](state_migration.ex)
- [Tests](../../../test/examples/04_runtime/04_14_state_migration/state_migration_test.exs)

Previous: [Stable Reference](../04_12_stable_reference/README.md) | Next: [Request Modes](../04_15_request_modes/README.md)

Read this lesson before [Definition Revision](../../10_persistence/10_08_definition_revision/README.md).
This lesson teaches the upgrade Action. The next lesson adds saved code
references and restore rejection. Together they form one upgrade path.
