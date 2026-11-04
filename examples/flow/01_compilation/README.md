# Flow compilation examples

These eight offline examples show how current Jido Flow authoring paths produce
canonical Flow data and a shallow dependency graph.

| ID | Lesson |
| --- | --- |
| `flow/01_01_single_step` | Build one data-authored Step. |
| `flow/01_02_dependency_graph` | Derive data and control dependencies. |
| `flow/01_03_dsl_flow` | Build the same data with the Flow DSL. |
| `flow/01_04_stored_json` | Decode a trusted JSON document. |
| `flow/01_05_authoring_equivalence` | Compare DSL, data, and JSON authoring. |
| `flow/01_06_validation` | Reject invalid references and cycles. |
| `flow/01_07_inputs_and_output` | Validate input and explicit output. |
| `flow/01_09_compiled_program` | Keep compound components shallow. |

Run the group with:

```sh
mix test.examples test/examples/flow/01_compilation
```
