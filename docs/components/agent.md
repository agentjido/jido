---
title: Jido.Agent component
status: current
last-reviewed: 2026-11-11
---

# Jido.Agent component

Purpose: Author fixed Agent definitions, construct immutable instance values,
and evaluate one Signal to a complete candidate state and runtime Directives.

Review result: All four checks have evidence (R10). The component boundary is
confirmed after the immutable-definition refactor. Agent owns no process,
persistence adapter, durable lifecycle, or ordinary definition mutation.

## Public contract

| Surface | Contract |
| --- | --- |
| `define/1`, `define!/1` | Build one neutral definition from a plain map. |
| `definition/1` | Return the neutral definition for a compiled module or Agent value. |
| `instantiate/2`, `instantiate!/2` | Build one identified instance with complete validated state. |
| `validate/1`, `definition?/1`, `instance?/1`, `schema/1` | Validate or inspect definition and instance shape and state schema. |
| `set/2` | Return a new instance with validated top-level domain-state replacements. Plugin-owned state is excluded. |
| `build_signal/3` | Build a causally linked Agent-owned Signal inside an Action context. |
| `cmd/3` | Run one process-free evaluation and return a candidate Agent and Directives, a Handoff, or an error. It does not commit or dispatch. |
| `use Jido.Agent` | Compile the DSL and generate `definition/0`, `instantiate/1`, `instantiate!/1`, `schema/0`, `vsn/0`, `cmd/3`, `route_executable!/1`, and named route Signal helpers. |

Optional `initialize/2`, `checkpoint/2`, and `restore/2` callbacks support
initial-state transformation and custom portable checkpoint representation.

The supporting public values are `Jido.Agent.Directive`, `Jido.Agent.Ref`,
`Jido.Agent.Topology`, and `Jido.Agent.View`. Codec behavior is reached through
the common Jido Codec boundary. Route is a public value contract. Runner,
Validation, Schema, Callback, DSL implementation, and Plugin pipeline modules
are internal.

## API use and proof

Compiled Agent modules, data-defined Agents, AgentServer startup and Turns,
Persistence checkpoints, Durable Agent execution, Plugins, AI Agents, views,
and examples use the same definition and instance contract. Agent tests cover
authoring equivalence, compilation diagnostics, route selection and
projection, state completeness, Directives, Plugin preparation and reduction,
static topology, Codec documents, references, views, Handoffs, and direct/live
semantic equivalence.

`cmd/3` selects a route and prepares one Flow instruction. An Action route is
authoring sugar for a one-step Flow. AgentServer decides transient or durable
host policy from persistence capability. Handler kind does not create another
Agent execution path.

## Duplication and Elixir design

The review removed `Jido.Agent.Turn`, Diff, Mutation, `mutate/2`, and the full
family of route, Plugin, connection, member, topology, and definition mutation
Directives. Ordinary evaluation now has one complete-state result and one
Directive batch. AgentServer no longer needs a second ordinary commit path for
Plugin replacement or topology reconciliation.

Definitions are fixed for one activation. Static topology stays in the
definition. Temporary children are AgentServer runtime operations. A permanent
definition change uses the separate idle-only whole-definition upgrade path:
trusted Codec document, explicit Catalog, optional state migration,
revision-controlled persistence, and restart under the same Agent Ref.

Keep Directive, Ref, Topology, View, Route, and Plugin preparation as proof
surfaces inside Agent. They have distinct values or pure behavior but do not
provide independent product capabilities outside the Agent definition and
evaluation contract.

## Findings and limits

- **F1 — API specification defect, P3.** The generated compiled-Agent `cmd/3`
  specification lists only success and error. It delegates to
  `Jido.Agent.cmd/3`, which can also return `{:handoff, candidate, instruction,
  directives}`. The implementation works, but the generated specification is
  incomplete.
- AgentServer and Plugin code changed to enforce the fixed-definition boundary.
  Those seam changes do not complete either parent component review.
- Whole-definition upgrade rejects active or waiting work. Migration of an
  active durable Flow is outside this version.

## Checks

Checkpoint `390d1c0f` passed formatting, warning-free compilation, 3,192
package tests with 111 normal exclusions, 246 examples, and all 321 active
Covenant obligations. The Agent suite currently has 41 focused test files.
Repository searches confirmed that removed mutation and Turn types remain only
in removal records and negative assertions.

## Sources

- [Public facade](../../lib/jido/agent.ex)
- [DSL](../../lib/jido/agent/dsl.ex)
- [Runner](../../lib/jido/agent/runner.ex)
- [Directives](../../lib/jido/agent/directive.ex)
- [Static topology](../../lib/jido/agent/topology.ex)
- [Reference](../../lib/jido/agent/ref.ex)
- [View](../../lib/jido/agent/view.ex)
- [Focused tests](../../test/jido/agent)
- [Agent obligations](../../test/contracts/jido/agent.obligations.md)
- [Agent evaluation obligations](../../test/contracts/jido/agent_evaluation.obligations.md)

