> Pending approval. Selected decisions are recorded below; other Agent questions remain open.

# Agent design

An earlier version of this document was approved on 2026-09-09.
The [design review index](../README.md#document-review-status) is the source of
truth for approval. Pending prerequisite seam details are explicit assumptions
for this Agent contract. A later conflict requires a reviewed migration.

## Current review decisions

On 2026-10-01, the user selected immediate validation and V3 write ownership
([GAP-006](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/GAP_ANALYSIS.md#gap-006)).
A successful `set/2` update validates the complete combined state. Callers do
not need a separate validation step. Related domain fields can be changed
in one call. Domain updates cannot change Plugin-owned fields; each Plugin
can replace only its own field. These decisions close the validation timing
and write ownership questions; they do not approve the complete document.
The selected deep merge change in GAP-005 is separate and is not yet implemented.

The user also selected the GAP-007 schema policy on 2026-10-01. Input
conversion occurs before values become Agent state. Creation applies and
checks defaults. Later validation checks stored values without changing
them. State schemas contain defaults and validation rules, not conversion
effects. The Zoi upstream and released-dependency work remains open under
GAP-062; it does not leave this contract undecided.

For GAP-008, the user selected rejection of nonportable saved values on
2026-10-01. Checkpoints are checked after custom Agent or Plugin persistence
conversion. Restore checks stored data before conversion, then validates
reconstructed live state. This decision concerns saved checkpoints, not a
new restriction on live state. Local values remain allowed when the live
schema permits them; resource reconstruction remains application or Plugin
work. The older blanket live-state ban is retired below.

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
`plugins`, ordered normalized `routes`, `metadata`, and `vsn`. Only `id` and
`state` differ between a definition and its instances.

The instance has one combined state map. The domain schema and stateful Plugin
schemas compose into one complete schema. Each Plugin-owned value stays under
its declared top-level key. There is no second Plugin state map. Domain code
and Plugins have separate write authority even though they share one map.

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

`AGT-REQ-005`: Retired. The blanket live-state handle ban conflicts with the
canonical code and the V2 fallback rule. Durable rejection remains in
AGT-REQ-036; live-state validation is stated in AGT-REQ-048.

`AGT-REQ-006`: When the Agent boundary instantiates a definition, it shall allow
instance overrides only for `id` and `state`.

`AGT-REQ-007`: When the Agent boundary constructs initial state, it shall merge
caller state over schema defaults and validate the complete result, including
the default values, before it accepts the Agent.

`AGT-REQ-046`: When an Agent state schema contains a transform, coercion,
Codec, Lazy, or StringBoolean conversion schema, the Agent schema validator
shall reject the schema.

`AGT-REQ-047`: When the Agent boundary validates existing state, it shall
check the stored values without substituting defaults or changing values.

`AGT-REQ-048`: When the Agent boundary validates live state, it shall not
reject a value solely because that value is nonportable.

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

`AGT-REQ-015`: When `set/2` receives domain attributes, the Agent boundary
shall return a new Agent only after it deep-merges the domain fields and
validates the complete combined state.

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

`AGT-REQ-043`: Where an Agent module does not define `handle_signal/2`, the
Agent boundary shall select the Turn from the Agent routes.

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

`AGT-REQ-042`: The Agent boundary shall not expose a general Agent-to-map
conversion function.

### Agent `vsn` and checkpoints

`AGT-REQ-026`: Where an Agent definition is owned by a generated Agent module,
the normalized definition shall contain one positive module-owned `vsn`.

`AGT-REQ-027`: Where an existing generated Agent module does not declare
`vsn`, the Agent authoring boundary shall use `vsn: 1`.

`AGT-REQ-028`: Where direct data owns the normalized definition, including a
definition derived from a generated module, or a behavior-only module owns no
generated definition, the Agent boundary shall permit an unversioned neutral
definition.

`AGT-REQ-029`: When Builder or Codec processes Agent `vsn`, the
Agent authoring boundary shall preserve that value.

`AGT-REQ-030`: When the default checkpoint boundary writes a versioned
module-owned Agent, it shall first verify that the validated neutral Agent
definition is strictly equal to the current generated module definition.

`AGT-REQ-031`: The persistence boundary shall write Agent snapshots in exact
format 1.

`AGT-REQ-032`: The persistence boundary shall read only exact snapshot format 1
and shall reject earlier Agent and snapshot shapes.

`AGT-REQ-033`: When the default snapshot boundary writes an Agent, it shall
write a plain map with `format`, complete `agent`, `references`, and
`state_format` fields. The complete Agent contains its `vsn`, ID, definition,
and combined state.

`AGT-REQ-034`: When restore reads a default format-1 snapshot, the Agent
boundary shall verify code references and validate the complete saved Agent
before it accepts saved state.

`AGT-REQ-035`: While complete custom checkpoint and restore callbacks remain
supported, their callback boundary shall keep the documented opaque plain-map
payload contract.

`AGT-REQ-040`: When a custom checkpoint callback returns a new payload, the
public persistence boundary shall store it in the same format-1 snapshot with
`state_format: :custom`. Restore shall verify saved code references before it
passes the opaque payload to the callback.

`AGT-REQ-044`: Where an Agent module does not define `checkpoint/2`, the Agent
boundary shall use the core format-1 snapshot behavior.

`AGT-REQ-045`: Where an Agent module does not define `restore/2`, the Agent
boundary shall use the core format-1 restore behavior for a default snapshot.

`AGT-REQ-041`: While direct and behavior-only Agent definitions remain valid
in memory, the Agent boundary shall not apply state portability rules to their
static definition data. Their default embedded-definition checkpoint shall be
durable only when the complete checkpoint is portable. If it is not portable,
the boundary shall return the seam-12 `ValidationError` with code
`:non_portable_term` and a bounded checkpoint path.

### Portable state and errors

`AGT-REQ-036`: When checkpoint creation accepts converted output or restore
accepts stored checkpoint input, the Agent boundary shall reject every
nonportable term at any depth.

`AGT-REQ-037`: If checkpoint portability validation fails, then the Agent
boundary shall return the seam-12 `ValidationError` with code
`:non_portable_term` and a bounded path from `:checkpoint`.

`AGT-REQ-038`: Retired. There is no general live-instance portability rule.
AGT-REQ-041 still defines portability of embedded durable definitions.

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
| `vsn` | Positive integer or `nil` | Same | Module-owned meaning revision; `nil` is for unversioned compatibility forms. |
| `id` | `nil` | Nonempty binary | Current Agent ID only; Agent Ref belongs to seam 03. |
| `state` | `nil` | Plain map | Sole complete state map with domain and Plugin-owned fields. |

### Functions and callbacks

| Entry | Contract |
| --- | --- |
| `new/1`, `new!/1` | Construct a neutral definition. |
| Generated `MyAgent.new/1`, `MyAgent.new!/1` | Construct an instance from the generated Agent module definition. |
| `instantiate/2`, `instantiate!/2` | Construct an instance from a neutral definition. |
| `validate/1`, `validate_definition/1`, `validate_instance/1` | Validate the applicable Agent form. |
| `definition?/1`, `instance?/1`, `definition/1` | Inspect or derive the two forms. |
| `complete_schema/1`, `complete_schema!/1` | Return the domain schema combined with all Plugin-owned field schemas. |
| `set/2` | Deep-merge domain fields and validate the complete combined state. |
| `cmd/3` | Evaluate directly and return a candidate Agent and Directives. |
| `checkpoint/2`, `restore/3` | Use the Agent checkpoint and restore boundary with an optional context map. |
| `handle_signal/2` | Return a prepared Turn or an error. Seam 04 owns route policy. |
| `checkpoint/2`, `restore/2` callbacks | Let an Agent module encode and decode an opaque custom payload. The public Agent boundary owns the revision envelope. |

`Jido.Agent` has no general `to_map/1` function. Use `Jido.Agent.Codec` for a
portable definition document and the checkpoint boundary for identity and live
state. Read public struct fields directly for local inspection.

The current snapshot is this format-1 plain map:

```elixir
%{
  format: 1,
  agent: %Jido.Agent{id: "agent-1", vsn: 3, state: complete_combined_state},
  references: %{MyApp.Agent => code_fingerprint},
  state_format: :default
}
```

It stores the accepted complete Agent and does not add a public Snapshot struct.
Direct and behavior-only definitions use the same format when the complete
snapshot is portable. Earlier Agent and snapshot shapes are not read.

A custom callback returns an opaque map. The public Agent boundary writes this
core-owned envelope:

```elixir
%{
  version: 2,
  kind: :agent_custom,
  agent_module: MyApp.Agent,
  vsn: 3,
  payload: custom_callback_map
}
```

Restore checks the module and `vsn` before it gives `payload` to the custom
callback. Restore rejects a raw custom payload without the V3 envelope.

The portability rule applies to checkpoint output after conversion and to
stored input before restore conversion. It does not apply to live instance
state or to the static definition while the definition stays in memory.
Static Zoi schemas and Router match declarations can contain valid static
function data. An embedded direct definition must be portable before the
default checkpoint can cross a durable boundary.

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
- `AGT-INV-008`: Agent `vsn`, checkpoint format version, Agent Server
  state version, and persistence storage revision are separate concepts.

## Downstream guarantees

These approved guarantees apply to dependent seams.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 02 Agent authoring | Module DSL, direct data, Builder, and Codec keep one normalized definition and preserve revision. |
| 03 Agent identity | An instance keeps its current nonempty ID; this seam does not define Agent Ref, namespace, or location. |
| 04 Turn evaluation | Direct evaluation accepts one prepared Turn and returns one candidate Agent and Directive list; route order remains owned by seam 04. |
| 05 Plugins | Plugin-owned fields stay in the combined state map with unique keys and separate write authority; facet details remain owned by seam 05. |
| 07 Persistence | Agent snapshots use format 1 with Agent `vsn`; record fields remain owned by seam 07. |
| 08 Agent Server | Live evaluation uses the same candidate assembly; commit and state version remain outside the Agent value. |
| 12 Errors and contracts | Agent operations adopt approved errors and early portable-state checks without inventing interim error shapes. |

## Approved design decisions

| ID | Question | Approved option | Effect |
| --- | --- | --- | --- |
| `AGT-DEC-001` | Which current Agent contracts remain? | Keep both forms, combined state, direct `cmd/3`, Builder, Codec, custom routing, and checkpoint callbacks. | No current supported path is removed. |
| `AGT-DEC-002` | How does Agent `vsn` start? | Default generated modules to `vsn: 1`; allow `nil` only for direct and behavior-only compatibility forms. | Existing module source stays valid. |
| `AGT-DEC-003` | How does snapshot creation prove code identity? | Save fingerprints for every referenced module and verify them before restore. | Restore fails when referenced code changed or is unavailable. |
| `AGT-DEC-004` | Which default snapshot format does V3 use? | Use one exact format-1 plain map that contains the complete accepted Agent. | Restore keeps the accepted definition without a public struct or a legacy reader. |
| `AGT-DEC-005` | Where does state portability run? | Run it at every Agent state acceptance point and keep persistence validation. | Direct and persistent Agents use one state rule. |
| `AGT-DEC-006` | Does this seam add state accessor APIs? | No. Keep struct access, `set/2`, and the private complete transition boundary. | The seam does not add an unproved public abstraction. |
| `AGT-DEC-007` | How does a custom checkpoint carry code identity? | Use the same format-1 snapshot and mark the state payload as custom. | Custom callbacks retain payload ownership and restore verifies referenced code first. |
| `AGT-DEC-008` | Which direct definitions use the default durable format? | Keep every valid direct definition in memory, but permit the embedded default checkpoint only when its full map is portable. | Runtime authoring stays flexible and durable writes fail with a typed path instead of hidden serialization risk. |
