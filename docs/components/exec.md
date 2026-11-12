---
title: Jido.Exec component
status: current
last-reviewed: 2026-11-11
---

# Jido.Exec component

Purpose: Compile and run Jido Actions and Flows through one Runic execution
model.

Review result: All four checks have evidence (R9). The public boundary is
small and confirmed. The review included the later component-by-component
Flow-to-Runic mapping and the completed simplification, not only the earlier
Exec design discussion.

## Public contract

| Surface | Contract |
| --- | --- |
| `Jido.Exec.compile/2` | Resolve an Action, Instruction, Flow module, or Flow value and return one `Runic.Workflow`. An Action first becomes a canonical one-step Flow. |
| `Jido.Exec.run/4` | Run that same compilation path to completion in an isolated supervised task. Return output and effects, a terminal Handoff, or an error. Do not dispatch effects. |
| `Jido.Exec.result/2` | Project one observed Runic execution occurrence to the normal Jido result contract. |
| `Jido.Exec.supports?/2` | Let an Action check a capability supplied by its current host. The current public capability is waits. |
| `Jido.Exec.Wait` | Own portable wait identity, matching, input receipts, deadlines, selection, and result values. |

`compile/2` plus Runic is the advanced stepwise and inspection escape hatch.
It is not a second Jido execution API. `run/4` compiles and executes the same
Workflow without exposing Runic to normal Jido callers.

## API use and proof

Agent direct evaluation, AgentServer transient execution, Durable execution,
AI reasoning, examples, and Exec tests all use this contract. Compile tests
cover Step, Choice, Parallel, Map, Reduce, Iterate, Invoke, Subflow, Wait, and
Handoff mappings. Execution tests cover task failure, timeout, policy,
concurrency, context, stored Flows, source paths, observations, and effects.

The current Covenant IDs retain the earlier package ownership names. The
important proof is split between execution, boundary, Agent evaluation,
Durable, and AgentServer obligations. That split is a proof-layout concern;
it does not create more Exec components.

## Duplication and Elixir design

The review removed the separate direct-Action execution path, `call_action`,
the unscoped result API, public managed execution setup, and the second graph
interpretation. Flow is the authoring graph and Runic Workflow is the execution
graph. Compiler nodes lower each compound Flow component to the Runic behavior
that it needs.

Keep Compiler, Runtime, Result, ActionBoundary, Fact, ValueResolver, Wait, and
the Runic node implementations as internal owners. They separate compilation,
host policy, observation projection, Action isolation, local values, binding
resolution, and workflow behavior. They are not independent public
sub-components.

Runic owns runnable preparation, graph state, execution policy, history, and
checkpoint mechanics. Jido owns Flow semantics, input and output validation,
effect terms, source-aware errors, waits, and the Jido result contract.

## Findings and limits

- No remaining duplicate public execution path was confirmed.
- Internal Runic protocol functions are exported because Runic calls them;
  their modules have hidden documentation and are not public Jido APIs.
- Stepwise execution has more setup friction by design. It uses `compile/2`
  and Runic directly.
- External work performed by an Action is not made transactional by Exec.

## Checks

The integrated R10 checkpoint passed warning-free compilation, formatting,
3,192 package tests with 111 normal exclusions, 246 examples, and all 321
active Covenant obligations. The Exec suite currently has 30 focused test
files. These checks prove the integrated boundary after the R9 refactor.

## Sources

- [Public facade](../../lib/jido/exec.ex)
- [Compiler](../../lib/jido/exec/compiler.ex)
- [Runtime](../../lib/jido/exec/runtime.ex)
- [Result projection](../../lib/jido/exec/result.ex)
- [Wait value](../../lib/jido/exec/wait.ex)
- [Node implementations](../../lib/jido/exec/node)
- [Focused tests](../../test/jido/exec)

