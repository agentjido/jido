# 08_14 Offline Snapshot Migration

One snapshot upgrade Action changes the definition and state of an inactive
portable Agent snapshot.

## Read and run

Read [the Agent and upgrade Action](state_migration.ex), then
[the tests](state_migration_test.exs).

```sh
mix test.examples examples/08_runtime/08_14_state_migration
```

`Jido.Persistence.upgrade/3` is an offline data operation. It does not contact
an AgentServer. The Action receives `%{snapshot: snapshot}` and returns one
complete portable snapshot with no Directives. A later restore uses that saved
definition and state.

Use `Jido.AgentServer.upgrade/3` for an idle running activation. That API takes
a complete trusted Agent Codec document and can use a separate state migration
Action or Flow. See [Whole Definition Upgrade](../08_12_definition_changes/README.md).

Previous: [Stable Reference](../08_13_stable_reference/README.md) |
Next: [Pending Job Recovery](../08_15_pending_job_recovery/README.md)
