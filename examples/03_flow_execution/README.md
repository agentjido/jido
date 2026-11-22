# 03 Flow Execution

These offline examples use one execution model. `Jido.Exec.run/4` lowers an
Action or Flow to a Runic workflow and runs it to completion. Each authored
Flow component becomes one Runic component.

Read the lessons in order. Where a pattern has two runnable steps, start
with the small example and continue to the application.

- [Single action](03_01_single_action/README.md). Lower one Action to a one-Step Flow.
- [Steps and references](03_02_steps_and_references/README.md). Connect Steps with data references.
- [Choice](03_03_choice/README.md). Select the first matching branch. Continue with [Conditional routes](03_19_conditional_routes/README.md) to select a branch with a fallback.
- [Parallel](03_04_parallel/README.md). Run an ordered parallel group. Continue with [Parallel join](03_20_parallel_join/README.md) to join independent work.
- [Map](03_05_map/README.md). Apply one Action to an ordered collection.
- [Reduce](03_06_reduce/README.md). Fold an ordered collection into one value.
- [Iterate](03_07_iterate/README.md). Update state within a fixed iteration limit.
- [Subflow](03_08_subflow/README.md). Keep a child Flow behind one Subflow node. Continue with [Nested Flow](03_23_nested_flow/README.md) to use one Flow inside another Flow.
- [Invoke](03_09_invoke/README.md). Select an Action or Flow at run time.
- [Handoff](03_10_handoff/README.md). Return a successor Instruction.
- [Effects and failure](03_11_effects_and_failure/README.md). Return effects or one normalized error.
- [Wait and signal](03_12_wait_and_signal/README.md). Pause and resume through a host.
- [Direct Runic execution](03_13_compile_to_runic/README.md). Inspect and execute the compiled workflow. Continue with [Runic Runner](03_14_runic_runner/README.md) to dispatch the workflow one Runic unit at a time.
- [Human approval](03_15_human_approval/README.md). Address one approval event.
- [Sequential flow](03_17_sequential_flow/README.md). Connect ordered steps.
- [Effectful steps](03_18_effectful_steps/README.md). Pass an application service in execution context.
- [Ordered batch](03_21_ordered_batch/README.md). Bound concurrent Map work and preserve source order through Reduce.
- [Bounded iteration](03_22_bounded_iteration/README.md). Call a child Flow on each pass of a bounded repair loop.
- [Executable continuation](03_24_executable_continuation/README.md). Continue with an Action or Flow.
- [Flow directives](03_25_flow_directives/README.md). Return ordered Directives with Flow output.

The Runic lessons cover direct execution. Use `Jido.Exec.run/4` for normal application code.

Run the chapter with:

```sh
mix test.examples examples/03_flow_execution
```
