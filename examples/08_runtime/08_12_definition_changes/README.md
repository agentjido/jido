# 08_12 Whole Definition Upgrade

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
mix test.examples examples/08_runtime/08_12_definition_changes
```

The activation must be idle and supervised. The upgrade validates the complete
definition and migrated state, writes the new revision, and replaces the
AgentServer. It does not migrate active Flow work.

Previous: [Causal Trace](../08_11_causal_trace/README.md) |
Next: [Stable Reference](../08_13_stable_reference/README.md)
