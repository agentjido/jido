# 02_02 Dependency Graph

Result references and `needs` create separate data and control dependencies.

## What you will learn

- How result references add data edges.
- How `needs` adds control edges without passing a value.

## Read the code

Read [the Flow](dependency_graph.ex), then [the test](dependency_graph_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_02_dependency_graph --warnings-as-errors`

Expected result: `load` and `audit` are roots, `charge` follows `load`, and
`save` follows both branches.

## Important behavior

Dependency inspection uses the canonical Flow definition. It does not need a
running process.

## Limits

This lesson does not prove parallel scheduling or execution order.

## Files

- [Flow](dependency_graph.ex)
- [Tests](dependency_graph_test.exs)

[Previous: Single Step](../02_01_single_step/README.md) |
[Next: DSL Flow](../02_03_dsl_flow/README.md)
