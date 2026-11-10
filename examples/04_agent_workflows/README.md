# 04 Agent Workflows

These examples show how to compose Actions into Flows. Read them in order.
Each folder has a short guide, runnable source, and integration tests.

| Example | Main lesson |
| --- | --- |
| [04_01 Sequential Flow](04_01_sequential_flow/README.md) | Connect steps with result and control dependencies. |
| [04_02 Synchronous I/O Steps](04_02_effectful_steps/README.md) | Pass an I/O adapter through caller context and project the result. |
| [04_03 Choice and Fallback](04_03_conditional_routes/README.md) | Select the first matching Choice option and define a fallback. |
| [04_04 Parallel Join](04_04_parallel_join/README.md) | Run independent branches and join their results. |
| [04_05 Ordered Batch](04_05_ordered_batch/README.md) | Use Map and Reduce while you keep source order. |
| [04_06 Bounded Iteration](04_06_bounded_iteration/README.md) | Repeat a repair step with an explicit limit. |
| [04_07 Nested Flow](04_07_nested_flow/README.md) | Use one Flow as a step in another Flow. |
| [04_08 Executable Continuation](04_08_executable_continuation/README.md) | Continue execution with an Action or a Flow. |
| [04_09 Flow Directives](04_09_flow_directives/README.md) | Collect ordered Directives and dispatch them after one commit. |

Run all Workflow examples from the `jido` repository root:

```shell
mix test.examples test/examples/04_agent_workflows
```

The examples need no network access or credentials. They use small local
adapters when a lesson needs an external service boundary.

See [all examples](../README.md).
