# 02 Workflow examples

These examples show how to compose Actions into Flows. Read them in order.
Each folder has a short guide, runnable source, and integration tests.

| Example | Main lesson |
| --- | --- |
| [02_01 Sequential Flow](02_01_sequential_flow/README.md) | Connect steps with result and control dependencies. |
| [02_02 Effectful Steps](02_02_effectful_steps/README.md) | Pass an I/O adapter through caller context and project the result. |
| [02_03 Conditional Routes](02_03_conditional_routes/README.md) | Select the first matching Choice option and define a fallback. |
| [02_04 Parallel Join](02_04_parallel_join/README.md) | Run independent branches and join their results. |
| [02_05 Ordered Batch](02_05_ordered_batch/README.md) | Use Map and Reduce while you keep source order. |
| [02_06 Bounded Iteration](02_06_bounded_iteration/README.md) | Repeat a repair step with an explicit limit. |
| [02_07 Nested Flow](02_07_nested_flow/README.md) | Use one Flow as a step in another Flow. |
| [02_08 Executable Continuation](02_08_executable_continuation/README.md) | Continue execution with an Action or a Flow. |
| [02_09 Approval Workflow](02_09_approval_workflow/README.md) | Combine a search Flow, Agent commands, Plugin dispatch, and approval Signals. |

Run all Workflow examples from the `jido` repository root:

```shell
mix test --include example test/examples/02_workflow --seed 0
```

The examples need no network access or credentials. They use small local
adapters when a lesson needs an external service boundary.

See [all examples](../README.md) and the [example authoring rules](../AGENTS.md).
