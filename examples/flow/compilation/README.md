# Flow compilation examples

These eight offline examples show how current Jido Flow authoring paths produce
canonical Flow data and a shallow dependency graph.

| ID | Lesson |
| --- | --- |
| `flow/compilation/single_step` | Build one data-authored Step. |
| `flow/compilation/dependency_graph` | Derive data and control dependencies. |
| `flow/compilation/dsl_flow` | Build the same data with the Flow DSL. |
| `flow/compilation/stored_json` | Decode a trusted JSON document. |
| `flow/compilation/authoring_equivalence` | Compare DSL, data, and JSON authoring. |
| `flow/compilation/validation` | Reject invalid references and cycles. |
| `flow/compilation/inputs_and_output` | Validate input and explicit output. |
| `flow/compilation/compiled_program` | Keep compound components shallow. |

Run the group with:

```sh
mix test.examples test/examples/flow/compilation
```
