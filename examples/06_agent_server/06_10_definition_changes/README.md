# 06_10 Whole Definition Upgrade

Normal Agent work changes state. It does not change the Agent definition. An
administrator can replace one idle activation with a complete trusted Agent
document.

## What you will learn

- How the Agent Codec and a trusted Catalog define the complete replacement.
- How a migration Action returns the complete state for the new schema.
- How the stable Agent Ref remains valid when the AgentServer PID changes.

## Read the code

Read [the definitions](definition_changes.ex), then
[the behavior tests](definition_changes_test.exs).

## Run it

```sh
mix test.examples examples/06_agent_server/06_10_definition_changes --warnings-as-errors
```

## Important behavior

The activation must be idle and supervised. The upgrade validates the complete
definition and migrated state, writes the new revision, and replaces the
AgentServer. It does not migrate active Flow work.

## Limits

The upgrade does not move active Flow work or change the saved Agent origin.
Rollback must publish a later compatible definition version.

## Files

- [Definitions](definition_changes.ex)
- [Tests](definition_changes_test.exs)

Previous: [Runtime Inspection](../06_08_runtime_inspection/README.md) |
Next: [Logical Identity](../../07_instance_catalog_documents/07_04_logical_identity/README.md)
