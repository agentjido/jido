# 02_03 DSL Flow

The Flow DSL compiles to the same canonical data model as direct authoring.

## What you will learn

- How `use Jido.Flow` declares a Flow in code.
- How the DSL keeps the explicit output in the canonical definition.

## Read the code

Read [the DSL Flow](dsl_flow.ex), then [the test](dsl_flow_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_03_dsl_flow --warnings-as-errors`

Expected result: the compiled Flow has one `echo` component and one result
output.

## Important behavior

The DSL is an authoring form. It does not create a second Flow model.

## Limits

This lesson does not compare stored JSON or execute the Flow.

## Files

- [Flow](dsl_flow.ex)
- [Tests](dsl_flow_test.exs)

[Previous: Dependency Graph](../02_02_dependency_graph/README.md) |
[Next: Stored JSON](../02_04_stored_json/README.md)
