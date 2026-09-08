> Design navigation and review index. This document is pending approval.
> Code in `lib`, public module documentation, and executable tests define current behavior.

# Jido V3 design

Start with the [Jido V3 library vision](VISION.md). It defines the Bright Line,
the core semantic contract, developer ownership, and the library boundary used
by every architectural seam.

The numbered folders define the proposed review order for the main architectural seams. Each folder owns one subsystem or one cross-system concern. Its `README.md` states the boundary, current direction, and open questions.

The design documents are planning material. When a document and the implementation differ, treat the implementation as canonical until the design change is approved and implemented.

## Subsystem map

| Order | Architectural seam | Folder |
| --- | --- | --- |
| 00 | Core model, shared terms, and invariants | [Overview](00_overview/README.md) |
| 01 | Agent data model and state transitions | [Agent](01_agent/README.md) |
| 02 | Agent authoring and DSL | [Agent authoring](02_agent-authoring/README.md) |
| 03 | Stable Agent identity across processes and nodes | [Agent identity](03_agent-identity/README.md) |
| 04 | Turn evaluation and directive production | [Turn evaluation](04_turn-evaluation/README.md) |
| 05 | Plugin composition and scheduled behavior | [Plugins](05_plugins/README.md) |
| 06 | State commit, effects, and durability | [Commit and effects](06_commit-and-effects/README.md) |
| 07 | Persistence contracts and adapters | [Persistence](07_persistence/README.md) |
| 08 | Agent process runtime | [Agent Server](08_agent-server/README.md) |
| 09 | Runtime instance and application boundary | [Jido instance](09_jido-instance/README.md) |
| 10 | Runtime topology, ownership, and placement | [Runtime topology](10_runtime-topology/README.md) |
| 11 | Topology authoring and control plane | [Topology control plane](11_topology-control-plane/README.md) |
| 12 | Errors and public contracts | [Errors and contracts](12_errors-and-contracts/README.md) |
| 13 | Telemetry, logs, and operational visibility | [Observability](13_observability/README.md) |
| 90 | Package and extension boundaries | [Package boundaries](90_package-boundaries/README.md) |
| 99 | Delivery planning and retained design history | [Delivery and history](99_delivery/README.md) |

## Review method

Review each seam against the same five questions:

1. What does the current implementation do?
2. What target design do we want for V3?
3. What gaps exist between the current and target designs?
4. Which decisions must we make before implementation?
5. What evidence will show that the seam is aligned?

Cross-system decisions belong in [the architecture overview](00_overview/architecture.md) or [the invariants](00_overview/invariants.md). Detailed rules belong in the folder that owns the concept.

## Seam document pattern

Use [the architectural seam template](SEAM_TEMPLATE.md). Each seam has three
documents by default:

- `README.md` is the briefing and decision entry point.
- `design.md` is the planned end state and contains EARS requirements.
- `alignment.md` contains current evidence, gaps, migration phases, and the
  acceptance matrix.

Each seam README includes a short `Major gaps and work remaining` section.
Formal implementation tasks do not belong in these documents. After a seam is
approved, use `ce-plan` to create its implementation plan.

Do not keep separate briefing, gap-analysis, or evidence documents after their
unique content is integrated. This rule prevents the same fact from appearing
in several reports with different wording or status.

## Requirement format

Use EARS, the Easy Approach to Requirements Syntax, for all proposed and
approved requirements. EARS makes each requirement conditional, observable,
and testable.

Use these patterns:

| Pattern | Form |
| --- | --- |
| Ubiquitous | `The <owner> shall <required response>.` |
| Event-driven | `When <trigger>, the <owner> shall <required response>.` |
| State-driven | `While <state>, the <owner> shall <required response>.` |
| Unwanted behavior | `If <unwanted condition>, then the <owner> shall <required response>.` |
| Optional feature | `Where <feature is enabled>, the <owner> shall <required response>.` |
| Combined | `Where <feature>, while <state>, when <trigger>, the <owner> shall <required response>.` |

Give each requirement a stable identifier in the form
`<SEAM>-REQ-<number>`, such as `AGT-REQ-001`. Use one observable behavior per
requirement. Name the component that owns the response. Define each trigger,
state, input, result, and error with terms from the design glossary or the
owning seam.

Do not use words such as `should`, `normally`, `appropriate`, `fast`, or
`graceful` in a requirement. Replace each vague word with a measurable result.
Map every requirement to current evidence or to a required acceptance test.

An EARS statement does not mean that the requirement is approved. The review
status table remains the source of truth for approval.

## Document review status

This table is the source of truth for design approval. A moved or changed document remains pending until it receives a new review.

| Document | Status |
| --- | --- |
| Design index | Pending approval |
| [Architectural seam template](SEAM_TEMPLATE.md) | Pending approval |
| [Jido V3 library vision](VISION.md) | Pending approval |
| [Overview index](00_overview/README.md) | Pending approval |
| [Overview gap analysis](00_overview/gap-analysis.md) | Pending approval |
| [Architecture and data boundaries](00_overview/architecture.md) | Pending approval |
| [Cross-system invariants](00_overview/invariants.md) | Pending approval |
| [Glossary](00_overview/glossary.md) | Pending approval |
| [Overview alignment](00_overview/alignment.md) | Pending approval |
| [Overview review briefing](00_overview/briefing.md) | Pending approval |
| [Agent index](01_agent/README.md) | Pending approval |
| [Agent gap analysis](01_agent/gap-analysis.md) | Pending approval |
| [Agent design](01_agent/agent.md) | Pending approval |
| [Agent alignment](01_agent/alignment.md) | Pending approval |
| [Agent authoring index](02_agent-authoring/README.md) | Pending approval |
| [Agent authoring gap analysis](02_agent-authoring/gap-analysis.md) | Pending approval |
| [Agent authoring](02_agent-authoring/authoring.md) | Pending approval |
| [Agent DSL and interfaces](02_agent-authoring/dsl-and-interfaces.md) | Pending approval |
| [Stable Agent identity](03_agent-identity/README.md) | Pending approval |
| [Agent identity gap analysis](03_agent-identity/gap-analysis.md) | Pending approval |
| [Turn evaluation index](04_turn-evaluation/README.md) | Pending approval |
| [Turn evaluation gap analysis](04_turn-evaluation/gap-analysis.md) | Pending approval |
| [Turn evaluation](04_turn-evaluation/turn-evaluation.md) | Pending approval |
| [Plugin index](05_plugins/README.md) | Pending approval |
| [Plugin gap analysis](05_plugins/gap-analysis.md) | Pending approval |
| [Plugin design](05_plugins/plugins.md) | Pending approval |
| [Plugin facets and extension ownership](05_plugins/plugin-facets.md) | Pending approval |
| [Scheduled occurrences](05_plugins/scheduled-occurrences.md) | Pending approval |
| [Commit and effects index](06_commit-and-effects/README.md) | Pending approval |
| [Commit and effects gap analysis](06_commit-and-effects/gap-analysis.md) | Pending approval |
| [Commit and effects](06_commit-and-effects/commit-and-effects.md) | Pending approval |
| [Durability guarantee](06_commit-and-effects/durability-guarantee.md) | Pending approval |
| [Persistence index](07_persistence/README.md) | Pending approval |
| [Persistence gap analysis](07_persistence/gap-analysis.md) | Pending approval |
| [Instance persistence](07_persistence/instance-persistence.md) | Pending approval |
| [Persistence adapters and durable lifecycle](07_persistence/persistence-adapters.md) | Pending approval |
| [Agent Server index](08_agent-server/README.md) | Pending approval |
| [Agent Server gap analysis](08_agent-server/gap-analysis.md) | Pending approval |
| [Agent Server](08_agent-server/agent-server.md) | Pending approval |
| [Jido instance index](09_jido-instance/README.md) | Pending approval |
| [Jido instance gap analysis](09_jido-instance/gap-analysis.md) | Pending approval |
| [Jido instance](09_jido-instance/jido-instance.md) | Pending approval |
| [Jido instance callbacks](09_jido-instance/instance-callbacks.md) | Pending approval |
| [Runtime topology index](10_runtime-topology/README.md) | Pending approval |
| [Runtime topology gap analysis](10_runtime-topology/gap-analysis.md) | Pending approval |
| [Runtime topology](10_runtime-topology/runtime-topology.md) | Pending approval |
| [Remote owned children](10_runtime-topology/remote-owned-children.md) | Pending approval |
| [Topology control plane index](11_topology-control-plane/README.md) | Pending approval |
| [Topology control-plane gap analysis](11_topology-control-plane/gap-analysis.md) | Pending approval |
| [Topology authoring host](11_topology-control-plane/topology-authoring-host.md) | Pending approval |
| [Errors and contracts index](12_errors-and-contracts/README.md) | Pending approval |
| [Errors and contracts gap analysis](12_errors-and-contracts/gap-analysis.md) | Pending approval |
| [Error design](12_errors-and-contracts/errors.md) | Pending approval |
| [Observability index](13_observability/README.md) | Pending approval |
| [Observability gap analysis](13_observability/gap-analysis.md) | Pending approval |
| [Observability](13_observability/observability.md) | Pending approval |
| [Core OpenTelemetry bridge](13_observability/opentelemetry-bridge.md) | Pending approval |
| [Package boundaries index](90_package-boundaries/README.md) | Pending approval |
| [Package boundaries gap analysis](90_package-boundaries/gap-analysis.md) | Pending approval |
| [Runtime extension boundaries](90_package-boundaries/runtime-extension-boundaries.md) | Pending approval |
| [Delivery and history index](99_delivery/README.md) | Pending approval |
| [Delivery gap analysis](99_delivery/gap-analysis.md) | Pending approval |
| [Delivery plan](99_delivery/delivery-plan.md) | Pending approval |
| [V3 design changes](99_delivery/v3-design-changes.md) | Pending approval |
| [V3 planning baseline](99_delivery/planning-baseline.md) | Pending approval |

## Research evidence

- [Feature acceptance results](../examples/feature-acceptance-results.md)
- [Live upgrade results](../examples/live-upgrade-results.md)
- [Core refinement results](../examples/core-refinement-results.md)
