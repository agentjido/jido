# 02 Workflow examples

Each fixture uses the V3 command contract. Its tests check real framework behavior.
Run the full acceptance command from the repository root.

| Fixture | Source | Tests | Contract |
| --- | --- | --- | --- |
| 02_01_sequential_flow | [Source](02_01_sequential_flow/sequential_flow.ex) | [Tests](../../../test/examples/02_workflow/02_01_sequential_flow/sequential_flow_test.exs) | Input and output schemas, result dependencies, control dependencies, and one complete commit. |
| 02_02_effectful_steps | [Source](02_02_effectful_steps/effectful_steps.ex) | [Tests](../../../test/examples/02_workflow/02_02_effectful_steps/effectful_steps_test.exs) | Transient caller context, effect guards, explicit output projection, idempotency, and persistence. |
| 02_03_conditional_routes | [Source](02_03_conditional_routes/conditional_routes.ex) | [Tests](../../../test/examples/02_workflow/02_03_conditional_routes/conditional_routes_test.exs) | First-match Choice, lazy branch work, explicit failure capture, and selected-Action errors. |
| 02_04_parallel_join | [Source](02_04_parallel_join/parallel_join.ex) | [Tests](../../../test/examples/02_workflow/02_04_parallel_join/parallel_join_test.exs) | Concurrent independent steps, join dependencies, execution limits, failure, and cancellation. |
| 02_05_ordered_batch | [Source](02_05_ordered_batch/ordered_batch.ex) | [Tests](../../../test/examples/02_workflow/02_05_ordered_batch/ordered_batch_test.exs) | Ordered Map results, collected errors, fail-fast commit behavior, empty input, and serial Reduce. |
| 02_06_bounded_iteration | [Source](02_06_bounded_iteration/bounded_iteration.ex) | [Tests](../../../test/examples/02_workflow/02_06_bounded_iteration/bounded_iteration_test.exs) | Initial completion, exact loop bounds, and validation of initial and replacement state. |
| 02_07_nested_flow | [Source](02_07_nested_flow/nested_flow.ex) | [Tests](../../../test/examples/02_workflow/02_07_nested_flow/nested_flow_test.exs) | Separate child result scopes, shared context, child schemas, typed failures, and shared timeout. |
| 02_08_executable_continuation | [Source](02_08_executable_continuation/executable_continuation.ex) | [Tests](../../../test/examples/02_workflow/02_08_executable_continuation/executable_continuation_test.exs) | Dispatch, shared context and continuation budget, terminal output validation, and timeout. |
| 02_09_approval_workflow | [Source](02_09_approval_workflow/approval_workflow.ex) | [Tests](../../../test/examples/02_workflow/02_09_approval_workflow/approval_workflow_test.exs) | Separate approval Turns, post-commit Plugin dispatch, correlation, duplicates, and provider failure. |

See [all examples](../README.md) and [migration](../../../guides/migration.md).
