# Covenant and Reach realignment plan

Status: Prepared for execution after the Codec reduction.

This plan aligns Covenant component ownership with the enforced Reach layers.
It does not change production code by itself.

## Decision

Each Covenant component has one primary Reach layer.

The `modules:` list in a Covenant obligations file is an ownership and mutation
scope. Every module in that list must resolve to the same Reach layer. A module
must have no more than one primary Covenant owner.

A component test can call modules from lower Reach layers. Those modules are
dependencies. They do not belong in the component's `modules:` list.

For behavior that crosses layers, the component belongs to the highest layer
that owns the result. Its contract states the result at that boundary. The
lower-layer components keep their own rules and tests.

This gives the two tools separate jobs:

- Reach controls allowed code dependencies.
- Covenant controls one behavior owner and its proof.

## Required gate

Add a project check that reads `.reach.exs` and every Covenant obligations
file. The check must fail when:

1. A module does not match one Reach layer.
2. A component lists modules from more than one Reach layer.
3. Two components claim the same primary module.
4. A listed module does not exist.

The check must show the component, module, and resolved layer. Add the check to
CI after the current exceptions are removed.

Do not add a second manual layer field to each Covenant file. `.reach.exs` is
the source of truth. A copied field can become stale.

## Current cross-layer components

| Current component | Current layers | Realignment |
|---|---|---|
| `jido_action.authoring` | `primitives`, `value_model` | Retire the broad component. Move Catalog behavior to `jido.catalog`. Keep portable value behavior in `jido.codec`. Retain the current document router until its capabilities have direct owner APIs. |
| `jido_ai.conversation` | `value_model`, `capabilities` | Move Session and Thread behavior to `jido.conversation`. Keep only AI projection behavior in `jido.ai.conversation`. |
| `jido.plugin` | `definitions`, `agent_domain` | Put Config, Manifest, and Spec behavior in `jido.plugin.definition`. Keep the generic Plugin behavior and callback data in `jido.plugin`. |
| `jido.telemetry` | `primitives`, `live_runtime` | Put pure trace data in `jido.trace`. Keep runtime context and telemetry behavior in `jido.telemetry`. |
| `jido.agent_server.effects` | `agent_domain`, `live_runtime` | Keep Agent Directive rules in `jido.agent`. Keep effect execution, AgentServer directives, and reply gates in `jido.agent_server.effects`. |
| `jido.instance` | `agent_domain`, `live_runtime` | Put `Jido.Agent.Address` behavior in `jido.agent_reference`. Keep registry lookup, routing, options, and process ownership in `jido.instance`. |

Tests can still exercise a complete cross-layer path. For example, an Effects
test can submit an Agent Directive. The Effects component does not own the
Directive module or its internal validation.

## Current duplicate owners

These overlaps do not cross a Reach layer, but they make Covenant ownership
unclear:

- `Jido.Instruction.Config` is listed by both `jido_action.action` and
  `jido_action.inline`.
- `Jido.AgentServer.Lifecycle` is listed by `jido.agent_server`,
  `jido.agent_server.durable`, and `jido.agent_server.durable_turn`.
- `Jido.Persistence` is listed by `jido.persistence` and
  `jido.agent_server.durable`.

Keep each module in one primary `modules:` list. Other components can test its
public effect as a dependency. They must not mutate or regenerate it as owned
code.

## Codec prerequisite

Reduce Codec before the Covenant file moves. The current Codec namespace joins
unrelated compile-time, document, domain, and runtime concerns. A contract
rewrite before this reduction would preserve boundaries that the source no
longer needs.

Use this target:

| Current module or concern | Target owner | Reach layer |
|---|---|---|
| Small general `Jido.Codec` generator | `jido.codec.compiler` | `primitives` |
| `Jido.Instruction.Compiler` | `Jido.Instruction.Compiler`; `jido.instruction` | `definitions` |
| `Jido.Instruction.Config` | `Jido.Instruction.Config`; `jido.instruction` | `definitions` |
| `Jido.Agent.Codec` | `Jido.Agent.Codec`; `jido.agent` | `agent_domain` |
| `Jido.Flow.Codec.*` | `Jido.Flow.Codec.*`; `jido.flow` | `definitions` |
| `Jido.Signal.Codec` | `Jido.Signal.Codec`; `jido.signal` | `value_model` |
| Signal transport sanitation | `Jido.Signal.Boundary`, only when a production transport caller needs it | `value_model` |
| Signal telemetry preview | `Jido.Telemetry.Signal` | `live_runtime` |
| `Jido.Codec.Term` | `Jido.Codec.Term`; `jido.codec.term` | `primitives` |
| `Jido.Codec.Reference` | `Jido.Codec.Reference`; `jido.codec` | `value_model` |
| `Jido.Codec.Value` | `Jido.Codec.Value`; `jido.codec` | `value_model` |

Remove the global runtime document router, provider index, historical readers,
external fallback, and separate error and issue system unless a current
production caller proves a need. Do not create Covenant components for removed
code.

The reduced primitive Codec contract covers only the general compile-time JSON
codec behavior. Domain codecs stay with their domain components.

## Target component register

One Reach layer can contain many Covenant components. The register below is a
target, not a rule that one namespace must have one component.

| Reach layer | Target Covenant components |
|---|---|
| `primitives` | `jido.codec.compiler`, `jido.codec.term`, `jido.error`, `jido.expr`, `jido.id`, `jido.joi`, `jido.trace` |
| `value_model` | `jido.catalog`, `jido.conversation`, `jido.codec`, `jido.signal` |
| `definitions` | `jido.action`, `jido.action.inline`, `jido.action.output`, `jido.action.validation`, `jido.flow`, `jido.flow.inline`, `jido.instruction`, `jido.plugin.definition`, `jido.signal.routing` |
| `execution` | `jido.execution`, `jido.execution.action_boundary` |
| `agent_domain` | `jido.agent`, `jido.agent_evaluation`, `jido.agent_reference`, `jido.plugin` |
| `live_runtime` | `jido.agent_server` and its current focused subcomponents, `jido.instance`, `jido.persistence`, `jido.signal.delivery`, `jido.telemetry` |
| `capabilities` | `jido.ai.*` and the current `jido.plugin.*` bundled capability components |
| `composition` | `jido.application`, `jido.catalog.discovery` |

Create a component only for stable behavior that needs an independent contract.
Do not create an empty component only to mirror a namespace.

## Legacy component ID changes

Remove old package names from component IDs:

| Current ID | Target ID |
|---|---|
| `jido_action.expression` | `jido.expr` |
| `jido_action.action` | `jido.action` |
| `jido_action.inline` | `jido.action.inline` |
| `jido_action.output` | `jido.action.output` |
| `jido_action.validation` | `jido.action.validation` |
| `jido_action.flow` | `jido.flow` |
| `jido_action.inline_flow` | `jido.flow.inline` |
| `jido_action.instruction` | `jido.instruction` |
| `jido_action.codec` | Fold into `jido.flow`, or retire it with removed Codec behavior |
| `jido_action.execution` | `jido.execution` |
| `jido_action.boundary` | `jido.execution.action_boundary` |
| `jido_action.authoring` | Split as stated in this plan, then retire |
| `jido_ai.*` | `jido.ai.*` |

Change one component as one atomic slice. Move its obligations file, decision
records, survivor file, and test tags together. Update all `record`,
`invariant`, `depends_on`, and `superseded_by` references in the same slice.
Regenerate coverage after each slice.

## Execution order

1. Finish the Codec reduction and update Reach for each final Codec module.
2. Add the alignment report. Keep it out of CI while known failures remain.
3. Split the six current cross-layer components.
4. Remove duplicate module owners.
5. Rename all `jido_action.*` and `jido_ai.*` component IDs.
6. Add contracts for stable gaps: Id, Joi, Catalog, Signal, and application
   composition. Use existing tests when they already prove the behavior.
7. Enable the alignment check in CI.
8. Run focused Covenant checks and mutation checks for each changed component.
9. Run all final gates.

Do not combine a production namespace move and unrelated obligation edits in
one slice. A Codec namespace move and its matching contract move are one
related slice.

## Final gates

Run from `jido/`:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test
mix covenant.check --static
mix covenant.check
mix reach.check --arch --smells
```

Run `mix covenant.mutate <component>` for each component whose primary module
list or behavior changed.

The realignment is complete when:

- every production module matches exactly one Reach layer;
- every Covenant component owns modules from one Reach layer;
- every owned module has one primary Covenant component;
- no active component ID starts with `jido_action.` or `jido_ai.`;
- Covenant obligation coverage is 100 percent;
- Reach reports no dependency violation; and
- all tests pass.
