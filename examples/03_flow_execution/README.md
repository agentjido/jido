# 03 Flow Execution

These offline examples use one execution model. `Jido.Exec.run/4` lowers an
Action or Flow to a Runic workflow and runs it to completion. Each authored
Flow component becomes one Runic component.

The lessons follow the execution model in order:

1. `03_01_single_action` - lower one Action to a one-Step Flow.
2. `03_02_steps_and_references` - connect Steps with data references.
3. `03_03_choice` - select the first matching branch.
4. `03_04_parallel` - run an ordered parallel group.
5. `03_05_map` - apply one Action to an ordered collection.
6. `03_06_reduce` - fold an ordered collection into one value.
7. `03_07_iterate` - update state within a fixed iteration limit.
8. `03_08_subflow` - keep a child Flow behind one Subflow node.
9. `03_09_invoke` - select an Action or Flow at run time.
10. `03_10_handoff` - return a successor Instruction.
11. `03_11_effects_and_failure` - return effects or one normalized error.
12. `03_12_wait_and_signal` - pause and resume through a host.
13. `03_13_compile_to_runic` - inspect and execute the compiled workflow.
14. `03_14_runic_runner` - dispatch the workflow one Runic unit at a time.
15. `03_15_human_approval` - address one approval event.
16. `03_16_batch_processing` - bound concurrent Map work and Reduce it.
17. `03_17_sequential_flow` - connect ordered steps.
18. `03_18_effectful_steps` - pass an application service in execution context.
19. `03_19_conditional_routes` - select a branch with a fallback.
20. `03_20_parallel_join` - join independent work.
21. `03_21_ordered_batch` - preserve source order through Map and Reduce.
22. `03_22_bounded_iteration` - stop a repair loop at an explicit limit.
23. `03_23_nested_flow` - use one Flow inside another Flow.
24. `03_24_executable_continuation` - continue with an Action or Flow.
25. `03_25_flow_directives` - return ordered Directives with Flow output.

Lessons 13 and 14 are advanced Runic escape paths. Normal application code
uses `Jido.Exec.run/4`.

Run the chapter with:

```sh
mix test.examples examples/03_flow_execution
```
