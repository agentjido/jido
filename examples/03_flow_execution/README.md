# 03 Flow Execution

These 14 offline examples use one execution model. `Jido.Exec.run/4` lowers an
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

The last two lessons are advanced escape hatches. Normal application code uses
`Jido.Exec.run/4`.

Run the chapter with:

```sh
mix test.examples examples/03_flow_execution
```
