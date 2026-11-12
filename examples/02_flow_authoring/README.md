# 02 Flow Authoring

These eight offline examples show how current Jido Flow authoring paths produce
canonical Flow data and a shallow dependency graph.

| ID | Lesson |
| --- | --- |
| `02_01_single_step` | Build one data-authored Step. |
| `02_02_dependency_graph` | Derive data and control dependencies. |
| `02_03_dsl_flow` | Build the same data with the Flow DSL. |
| `02_04_stored_json` | Decode a trusted JSON document. |
| `02_05_authoring_equivalence` | Compare DSL, data, and JSON authoring. |
| `02_06_validation` | Reject invalid references and cycles. |
| `02_07_inputs_and_output` | Validate input and explicit output. |
| `02_08_compiled_program` | Keep compound components shallow. |

Run the group with:

```sh
mix test.examples examples/02_flow_authoring
```
