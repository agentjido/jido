> Target seam design. This document is pending approval.

# Agent design

All requirements and decisions in this document are recommended targets. The
[design review index](../README.md#document-review-status) is the source of
truth for approval. The prerequisite seam documents are also pending approval.

## Scope and owner

- Owner: `Jido.Agent` and its private validation and direct-evaluation support.
- In scope: the immutable Agent value, definition and instance forms,
  normalized static data, combined state, construction and validation,
  immutable state changes, direct `cmd/3`, and Agent checkpoint and restore.
- Out of scope: route selection and Turn order, Agent Ref and runtime identity,
  Plugin facets and callback authority, commit rules, persistence records,
  Agent Server behavior, and runtime topology.
- Adjacent owners: `jido_action` owns Action, Flow, and execution behavior.
  `jido_signal` owns Signal and Router behavior. Seams 02, 04, 05, 07, 08, and
  12 own the related authoring, Turn, Plugin, persistence, live-runtime, and
  error details.

## Model

One `%Jido.Agent{}` type has two complete forms:

```text
neutral definition
  static fields + id: nil + state: nil
          |
          | instantiate with ID and initial state
          v
Agent instance
  same static fields + nonempty ID + one complete state map
```

The static fields are `module`, `name`, `description`, `schema`, ordered
`plugins`, ordered normalized `routes`, and `metadata`. A compatible target
also adds `definition_revision`. Only `id` and `state` differ between a
definition and its instances.

The instance has one combined state map. The domain schema and stateful Plugin
schemas compose into one complete schema. Plugin state stays under each
Plugin-owned top-level key. Domain code and Plugins have separate write
authority even though they share one value.

Direct evaluation has this boundary:

```text
Agent instance + Signal + options
  -> shared candidate evaluation
  -> validated candidate Agent + ordered Directives
```

It does not start a process, commit state, or handle Directives.

## Requirements

### Value forms and construction

`AGT-REQ-001`: The Agent boundary shall represent a neutral definition and an
Agent instance as two valid forms of `%Jido.Agent{}`.

`AGT-REQ-002`: The Agent boundary shall represent a neutral definition with
`id: nil`, `state: nil`, and complete validated static definition data.

`AGT-REQ-003`: The Agent boundary shall represent an Agent instance with a
nonempty binary ID, one complete validated state map, and the same normalized
static data as its source definition.

`AGT-REQ-004`: If an Agent value has only one of instance ID or instance state,
then the Agent validator shall reject it as an incomplete Agent.

`AGT-REQ-005`: The Agent instance shall contain no PID, task, monitor, timer,
or other live runtime handle.

`AGT-REQ-006`: When the Agent boundary instantiates a definition, it shall allow
instance overrides only for `id` and `state`.

`AGT-REQ-007`: When the Agent boundary constructs initial state, it shall merge
caller state over schema defaults and validate the complete result.

`AGT-REQ-008`: When an Agent definition comes from module DSL, direct data,
Builder, or Codec, the Agent boundary shall use one normalized definition
contract.

`AGT-REQ-009`: Where an Agent uses a generated module constructor, the
generated constructor shall delegate to the canonical Agent constructor.

### Combined state and write ownership

`AGT-REQ-010`: Where an Agent declares stateful Plugins, the Agent boundary
shall compose the domain schema and each unique Plugin-owned top-level state
field into one complete state schema.

`AGT-REQ-011`: The Agent boundary shall keep domain state and Plugin-owned state
in one complete Agent state map.

`AGT-REQ-012`: When an executable proposes state, the Agent boundary shall
reject a change to a Plugin-owned state field.

`AGT-REQ-013`: When a stateful Plugin contributes state, the Plugin boundary
shall allow it to replace only its own complete top-level state field.

`AGT-REQ-014`: When executable output and Plugin contributions are complete,
the Agent boundary shall validate one complete candidate state map.

`AGT-REQ-015`: When `set/2` receives valid domain attributes, the Agent
boundary shall deep-merge only domain fields and return a new validated Agent.

`AGT-REQ-016`: When the internal transition boundary receives complete valid
state, the Agent boundary shall replace the full state map and return a new
Agent without changing the source Agent.

### Direct evaluation

`AGT-REQ-017`: The Agent boundary shall provide `cmd/3` for evaluation without
an Agent Server or Jido instance.

`AGT-REQ-018`: When direct `cmd/3` succeeds, the Agent boundary shall return
`{:ok, candidate_agent, directives}`.

`AGT-REQ-019`: When direct `cmd/3` returns a candidate, the Agent boundary shall
not commit that candidate or handle its Directives.

`AGT-REQ-020`: When direct and live paths evaluate the same prepared Turn, the
Agent boundary shall use the same candidate assembly and validation boundary.

`AGT-REQ-021`: Where an Agent module defines a custom `handle_signal/2`
callback, the Agent boundary shall use its valid `Jido.Agent.Turn` as the
prepared Turn.

### Public compatibility boundaries

`AGT-REQ-022`: While no approved migration removes neutral definitions, the
Agent boundary shall keep their construction, validation, inspection, and
instantiation boundary supported.

`AGT-REQ-023`: While no approved migration removes Builder, the Agent authoring
boundary shall keep Builder as a supported path to the normalized definition
validator.

`AGT-REQ-024`: While no approved migration removes Codec, the Agent authoring
boundary shall keep Codec as a supported path to the normalized definition
validator.

`AGT-REQ-025`: The Agent boundary shall keep Codec authoring documents separate
from Agent checkpoint data.

### Definition revision and checkpoints

`AGT-REQ-026`: Where an Agent definition is owned by a generated Agent module,
the normalized definition shall contain one positive module-owned definition
revision.

`AGT-REQ-027`: Where an existing generated Agent module does not declare a
definition revision, the Agent authoring boundary shall use revision `1`.

`AGT-REQ-028`: Where direct data or a behavior-only module owns no generated
definition, the Agent boundary shall permit an unversioned neutral definition.

`AGT-REQ-029`: When Builder, Codec, or `to_map/1` processes a definition
revision, the Agent authoring boundary shall preserve that revision.

`AGT-REQ-030`: When the default checkpoint boundary writes a versioned
module-owned Agent, it shall first verify that the validated neutral Agent
definition is strictly equal to the current generated module definition.

`AGT-REQ-031`: When `checkpoint/2` uses the default version-1 format, the Agent
boundary shall keep the current map shape and combined state meaning.

`AGT-REQ-032`: When `restore/3` receives a valid default version-1 checkpoint,
the Agent boundary shall keep the current module-definition and embedded-
definition restore paths without a revision guarantee.

`AGT-REQ-033`: When the default checkpoint boundary writes a versioned
module-owned Agent, it shall write a version-2 plain map with `version`, `kind`,
`agent_module`, `definition_revision`, `id`, and combined `state` fields.

`AGT-REQ-034`: When restore reads a default version-2 checkpoint, the Agent
boundary shall reject an Agent module or definition revision mismatch before
it accepts saved state.

`AGT-REQ-035`: While complete custom checkpoint and restore callbacks remain
supported, the Agent boundary shall accept their documented plain-map
contract.

### Portable state and errors

`AGT-REQ-036`: When construction, state replacement, candidate assembly,
checkpoint creation, or restore accepts Agent state, the Agent boundary shall
reject every nonportable term at any depth.

`AGT-REQ-037`: If Agent state portability validation fails, then the Agent
boundary shall return the seam-12 `ValidationError` with code
`:non_portable_term` and a bounded path from `:agent_state`.

`AGT-REQ-038`: When the Agent boundary validates portable instance state, it
shall exclude normalized static definition data from the instance-state
portability rule.

`AGT-REQ-039`: If an Agent public operation fails, then the Agent boundary
shall use the approved seam-12 result and error rules, except for a registered
Elixir protocol control.

## Public contract

### Agent value

| Field | Definition | Instance | Contract |
| --- | --- | --- | --- |
| `module` | Module | Same | Behavior or generated Agent module. |
| `name`, `description` | Static | Same | Validated public description. |
| `schema` | Static | Same | Domain Zoi object before Plugin composition. |
| `plugins` | Ordered static list | Same | Canonical Plugin declarations. |
| `routes` | Ordered static list | Same | Canonical Router routes; route choice belongs to seam 04. |
| `metadata` | Static map | Same | Agent definition metadata. |
| `definition_revision` | Positive integer or `nil` | Same | Module-owned meaning revision; `nil` is for unversioned compatibility forms. |
| `id` | `nil` | Nonempty binary | Current Agent ID only; Agent Ref belongs to seam 03. |
| `state` | `nil` | Plain map | Complete combined domain and Plugin-owned state. |

### Functions and callbacks

| Entry | Contract |
| --- | --- |
| `new/1`, `new!/1` | Construct a neutral definition. |
| `new/2`, `new!/2` | Construct an instance from a generated Agent module. |
| `instantiate/2`, `instantiate!/2` | Construct an instance from a neutral definition. |
| `validate/1`, `validate_definition/1`, `validate_instance/1` | Validate the applicable Agent form. |
| `definition?/1`, `instance?/1`, `definition/1` | Inspect or derive the two forms. |
| `complete_schema/1`, `complete_schema!/1` | Return the combined domain and Plugin state schema. |
| `to_map/1` | Return the complete Agent value as a map for inspection and authoring support. It is not a checkpoint codec. |
| `set/2` | Deep-merge domain fields and validate the complete combined state. |
| `cmd/3` | Evaluate directly and return a candidate Agent and Directives. |
| `checkpoint/2`, `restore/3` | Use the Agent checkpoint and restore boundary with an optional context map. |
| `handle_signal/2` | Return a prepared Turn or an error. Seam 04 owns route policy. |
| `checkpoint/2`, `restore/2` callbacks | Let an Agent module keep its complete custom checkpoint behavior. |

The current default checkpoint remains a plain map:

```elixir
%{
  version: 1,
  kind: :agent,
  agent_module: MyApp.Agent,
  id: "agent-1",
  definition: neutral_definition,
  state: complete_combined_state
}
```

The recommended compatible extension is this version-2 plain map:

```elixir
%{
  version: 2,
  kind: :agent,
  agent_module: MyApp.Agent,
  definition_revision: 3,
  id: "agent-1",
  state: complete_combined_state
}
```

It does not copy the static definition into the checkpoint and does not add a
public Checkpoint struct. Version 1 remains readable. A generated module
definition uses version 2 after the revision contract is available. Direct and
behavior-only definitions can keep the embedded version-1 path until their
owner seam approves another compatible format.

The portable-state rule applies to instance state and checkpoint state. It does
not apply to the static definition as one recursive term. Static Zoi schemas
and Router match declarations can contain valid static function data.

## Invariants

- `AGT-INV-001`: Every Agent value is either a complete neutral definition or
  a complete instance. It is not a half-instance.
- `AGT-INV-002`: An instance and its source definition differ only in `id` and
  `state`.
- `AGT-INV-003`: Domain state and Plugin-owned state share one complete map but
  have separate write owners.
- `AGT-INV-004`: Candidate acceptance validates the complete combined state.
- `AGT-INV-005`: An Agent value is immutable and has no runtime handle.
- `AGT-INV-006`: Direct evaluation returns a candidate. It does not perform a
  live commit or Directive handling.
- `AGT-INV-007`: Codec data and checkpoint data have separate purposes and
  formats.
- `AGT-INV-008`: Definition revision, checkpoint format version, Agent Server
  state version, and persistence storage revision are separate concepts.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 02 Agent authoring | Module DSL, direct data, Builder, and Codec keep one normalized definition and preserve revision. |
| 03 Agent identity | An instance keeps its current nonempty ID; this seam does not define Agent Ref, namespace, or location. |
| 04 Turn evaluation | Direct evaluation accepts one prepared Turn and returns one candidate Agent and Directive list; route order remains owned by seam 04. |
| 05 Plugins | Plugin-owned fields stay in the combined state map with unique keys and separate write authority; facet details remain owned by seam 05. |
| 07 Persistence | Version-1 checkpoints remain readable; a compatible versioned-module format adds definition revision; record fields remain owned by seam 07. |
| 08 Agent Server | Live evaluation uses the same candidate assembly; commit and state version remain outside the Agent value. |
| 12 Errors and contracts | Agent operations adopt approved errors and early portable-state checks without inventing interim error shapes. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `AGT-DEC-001` | Which current Agent contracts remain? | Keep both forms, combined state, direct `cmd/3`, Builder, Codec, custom routing, and checkpoint callbacks. | No current supported path is removed. |
| `AGT-DEC-002` | How does definition revision start? | Default generated modules to revision `1`; allow `nil` only for direct and behavior-only compatibility forms. | Existing module source stays valid. |
| `AGT-DEC-003` | How does checkpoint creation prove module ownership? | Compare the validated neutral instance definition with the current generated module definition by strict term equality before a version-2 write. | Mutated static data cannot claim the module revision. |
| `AGT-DEC-004` | How does the default checkpoint evolve? | Add a version-2 plain map for versioned generated modules; keep version-1 reads and custom callback maps. | Restore gets a revision gate without a forced public struct. |
| `AGT-DEC-005` | Where does state portability run? | Run it at every Agent state acceptance point and keep persistence validation. | Direct and persistent Agents use one state rule. |
| `AGT-DEC-006` | Does this seam add state accessor APIs? | No. Keep struct access, `set/2`, and the private complete transition boundary. | The seam does not add an unproved public abstraction. |
