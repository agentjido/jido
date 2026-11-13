# 06_10 Whole Definition Upgrade

Normal Agent work changes state. It does not change the Agent definition. An
administrator can replace one idle activation with a complete trusted Agent
document.

## What you will learn

- How the Agent Codec and a trusted Catalog define the complete replacement.
- How a migration Action returns the complete state for the new schema.
- How the stable Agent Ref remains valid when the AgentServer PID changes.

## Read and run

Read [the definitions](definition_changes.ex), then
[the behavior tests](definition_changes_test.exs).

```sh
mix test.examples examples/06_agent_server/06_10_definition_changes
```

The activation must be idle and supervised. The upgrade validates the complete
definition and migrated state, writes the new revision, and replaces the
AgentServer. It does not migrate active Flow work.

Previous: [Runtime Inspection](../06_08_runtime_inspection/README.md) |
Next: [Logical Identity](../../07_instance_catalog_documents/07_04_logical_identity/README.md)
