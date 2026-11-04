# Flow authoring tests

Run `mix test.authoring test/authoring/flows` from the repository root.
This suite checks an author's complete path from Action and Flow declarations to canonical data, stored JSON, diagnostics, and execution.
Focused unit and execution tests remain under `test/jido/flow` and `test/jido/exec`.

## Fixed source

Repository: `agentjido/jido_action`

Commit: `177e7a4ce4342a9a6b7bc668f540dafbd7169d54`

Source root: `test/authoring/**`

The fixed source has 12 test files, nine support assets, one README, and 60 declared tests or properties plus generated guide cases.

## Source dispositions

| Source asset | Target or evidence | Disposition |
| --- | --- | --- |
| `README.md` | `test/authoring/flows/README.md` | Adapted |
| `adversarial_test.exs` | `test/authoring/flows/adversarial_test.exs` | Adapted |
| `boundaries_test.exs` | `test/authoring/flows/boundaries_test.exs` | Adapted |
| `components_test.exs` | `test/authoring/flows/components_test.exs` | Adapted |
| `extension_test.exs` | `test/authoring/flows/extension_test.exs` | Adapted |
| `flow_edges_test.exs` | `test/authoring/flows/flow_edges_test.exs` | Adapted |
| `generated_graph_test.exs` | `test/authoring/flows/generated_graph_test.exs` | Adapted |
| `greeting_test.exs` | `test/authoring/flows/greeting_test.exs` | Adapted |
| `guides_test.exs` | `test/jido/flow/dsl/spark_surface_test.exs` and `test/examples/02_flow_authoring/**` | Superseded by current registered guide and example evidence |
| `inline_hostile_test.exs` | `test/authoring/flows/inline_hostile_test.exs` | Adapted |
| `rejections_test.exs` | `test/authoring/flows/rejections_test.exs` | Adapted |
| `schema_pipeline_test.exs` | `test/authoring/flows/schema_pipeline_test.exs` | Adapted |
| `source_boundary_test.exs` | `test/authoring/flows/source_boundary_test.exs` | Adapted |
| `support/adversarial.ex` | `test/authoring/support/flows/adversarial.ex` | Adapted |
| `support/boundaries.ex` | `test/authoring/support/flows/boundaries.ex` | Adapted |
| `support/components.ex` | `test/authoring/support/flows/components.ex` | Adapted |
| `support/extension.ex` | `test/authoring/support/flows/extension.ex` | Adapted |
| `support/flow_edges.ex` | `test/authoring/support/flows/flow_edges.ex` | Adapted |
| `support/greeting.ex` | `test/authoring/support/flows/greeting.ex` | Adapted |
| `support/hostile.ex` | `test/authoring/support/flows/hostile.ex` | Adapted |
| `support/missing_output.ex` | `test/authoring/support/flows/missing_output.ex` | Adapted |
| `support/saved_flow.json` | `test/authoring/support/flows/saved_flow.json` | Adapted; the source fixture already uses stored Flow version 2 |

## Adaptation rules

- Use `Jido.Catalog` instead of the removed authoring Registry.
- Use `Jido.Joi` instead of Zoi.
- Keep stored Flow version 2 and explicit typed Catalog identifiers.
- Assert current structured diagnostics instead of removed Action or Flow error structs.
- Reuse the current Flow builder, component, codec, and authoring compiler test helpers.
- Keep dynamic compilation serial and remove generated modules after each test.
