# 01_09 Agent Extension

Agent extensions lower custom static declarations into normal Agent data.

## What you will learn

- How a Spark DSL entity declares custom authoring syntax.
- How `Jido.Agent.Extension` assigns each foreign entity to its owner.
- How extensions lower in declaration order into ordinary metadata.
- Why unclaimed entities and invalid lowered data fail authoring.

## Read the code

Read [the two extensions and Agent](agent_extension.ex). `Labels` consumes only
label entities. It passes the remaining flag entity to `Flags`. The result is a
normal Agent definition with metadata, schema, and routes.

## Run it

```sh
mix test test/examples/01_basic/01_09_agent_extension --include example --seed 0
```

Expected result: lowering records both metadata values in declared extension
order. Pure construction starts no process. An unclaimed entity and invalid
lowered configuration are rejected.

## Important behavior

Lowering is static. It must not start a process, execute an Action, or contact
an external service. After lowering, the normal `Jido.Agent.new/1` validation
and execution contracts apply.

## Limits

Extensions add authoring syntax. They do not add another Agent runtime or a
validation bypass.

## Files

- [Source](agent_extension.ex)
- [Tests](../../../test/examples/01_basic/01_09_agent_extension/agent_extension_test.exs)

Previous: [Custom Signal Selection](../01_08_custom_signal_selection/README.md) | Next: [Workflow examples](../../02_workflow/README.md)
