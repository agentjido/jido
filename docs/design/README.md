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

Cross-system decisions belong in the [overview design](00_overview/design.md).
Current cross-system evidence and gaps belong in the
[overview alignment](00_overview/alignment.md). Detailed rules belong in the
folder that owns the concept.

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
| [Overview briefing](00_overview/README.md) | Pending approval |
| [Overview design](00_overview/design.md) | Pending approval |
| [Overview alignment](00_overview/alignment.md) | Pending approval |
| [Agent briefing](01_agent/README.md) | Pending approval |
| [Agent design](01_agent/design.md) | Pending approval |
| [Agent alignment](01_agent/alignment.md) | Pending approval |
| [Agent authoring briefing](02_agent-authoring/README.md) | Pending approval |
| [Agent authoring design](02_agent-authoring/design.md) | Pending approval |
| [Agent authoring alignment](02_agent-authoring/alignment.md) | Pending approval |
| [Agent identity briefing](03_agent-identity/README.md) | Pending approval |
| [Agent identity design](03_agent-identity/design.md) | Pending approval |
| [Agent identity alignment](03_agent-identity/alignment.md) | Pending approval |
| [Turn evaluation briefing](04_turn-evaluation/README.md) | Pending approval |
| [Turn evaluation design](04_turn-evaluation/design.md) | Pending approval |
| [Turn evaluation alignment](04_turn-evaluation/alignment.md) | Pending approval |
| [Plugin briefing](05_plugins/README.md) | Pending approval |
| [Plugin design](05_plugins/design.md) | Pending approval |
| [Plugin alignment](05_plugins/alignment.md) | Pending approval |
| [Commit and effects briefing](06_commit-and-effects/README.md) | Pending approval |
| [Commit and effects design](06_commit-and-effects/design.md) | Pending approval |
| [Commit and effects alignment](06_commit-and-effects/alignment.md) | Pending approval |
| [Persistence briefing](07_persistence/README.md) | Pending approval |
| [Persistence design](07_persistence/design.md) | Pending approval |
| [Persistence alignment](07_persistence/alignment.md) | Pending approval |
| [Agent Server briefing](08_agent-server/README.md) | Pending approval |
| [Agent Server design](08_agent-server/design.md) | Pending approval |
| [Agent Server alignment](08_agent-server/alignment.md) | Pending approval |
| [Jido instance briefing](09_jido-instance/README.md) | Pending approval |
| [Jido instance design](09_jido-instance/design.md) | Pending approval |
| [Jido instance alignment](09_jido-instance/alignment.md) | Pending approval |
| [Runtime topology briefing](10_runtime-topology/README.md) | Pending approval |
| [Runtime topology design](10_runtime-topology/design.md) | Pending approval |
| [Runtime topology alignment](10_runtime-topology/alignment.md) | Pending approval |
| [Topology control-plane briefing](11_topology-control-plane/README.md) | Pending approval |
| [Topology control-plane design](11_topology-control-plane/design.md) | Pending approval |
| [Topology control-plane alignment](11_topology-control-plane/alignment.md) | Pending approval |
| [Errors and contracts briefing](12_errors-and-contracts/README.md) | Pending approval |
| [Errors and contracts design](12_errors-and-contracts/design.md) | Pending approval |
| [Errors and contracts alignment](12_errors-and-contracts/alignment.md) | Pending approval |
| [Observability briefing](13_observability/README.md) | Pending approval |
| [Observability design](13_observability/design.md) | Pending approval |
| [Observability alignment](13_observability/alignment.md) | Pending approval |
| [Package boundaries briefing](90_package-boundaries/README.md) | Pending approval |
| [Package boundaries design](90_package-boundaries/design.md) | Pending approval |
| [Package boundaries alignment](90_package-boundaries/alignment.md) | Pending approval |
| [Delivery briefing](99_delivery/README.md) | Pending approval |
| [Delivery design](99_delivery/design.md) | Pending approval |
| [Delivery alignment](99_delivery/alignment.md) | Pending approval |

## Delivery evidence

The [delivery alignment](99_delivery/alignment.md) records current quality,
test, research, documentation, package, compatibility, and release evidence.
Executable tests and repository automation remain the canonical evidence.
