# 12_09 Offline Snapshot Migration

One snapshot upgrade Action changes the definition and state of an inactive
portable Agent snapshot.

## What you will learn

- How to migrate one inactive portable snapshot.
- How the migration Action returns a complete definition and state.
- When to use offline persistence upgrade or live AgentServer upgrade.

## Read the code

Read [the Agent and upgrade Action](state_migration.ex), then
[the tests](state_migration_test.exs).

## Run it

```sh
mix test.examples examples/12_persistence/12_09_state_migration --warnings-as-errors
```

## Important behavior

`Jido.Persistence.upgrade/3` is an offline data operation. It does not contact
an AgentServer. The Action receives `%{snapshot: snapshot}` and returns one
complete portable snapshot with no Directives. A later restore uses that saved
definition and state.

Use `Jido.AgentServer.upgrade/3` for an idle running activation. That API takes
a complete trusted Agent Codec document and can use a separate state migration
Action or Flow. See [Definition Changes](../../06_agent_server/06_10_definition_changes/README.md).

## Limits

The offline operation does not quiesce, replace, or resume a running
activation. The application must keep both definition and state revisions
compatible.

## Files

- [Source](state_migration.ex)
- [Tests](state_migration_test.exs)

Previous: [Definition Revision](../12_08_definition_revision/README.md) |
Next: [Durable Execution](../../13_durable_execution/README.md)
