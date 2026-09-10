> Approved seam alignment. Dependent owner-seam follow-up remains open.

# Agent alignment

## Status

- Design reviewed: 2026-09-08. Approved: 2026-09-09.
- Code reviewed: working tree from `b02052402a6f1c4be10098c2d560831f14daec58`
  on branch `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md), and
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md). Overview
  is approved. The other two remain explicit assumptions for this approved
  seam and still require their own review.
- Alignment state: `Approved; scoped implementation complete`.

The review-status table in `docs/design/README.md` is the source of truth for
document approval.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): keeps direct Agent use, all supported
  authoring forms, explicit values, and developer-owned application structure.
- [Overview design](../00_overview/design.md): supplies approved requirements
  for two Agent roles, direct evaluation, Agent `vsn`, state write
  ownership, and compatibility.
- [Package-boundary design](../90_package-boundaries/design.md): keeps Jido as
  the Agent owner above public `jido_action` and `jido_signal` contracts.
- [Errors and contracts design](../12_errors-and-contracts/design.md): supplies
  pending error, protocol-control, and portable-value rules.
- [Target design](design.md): defines the approved Agent target.

### Canonical code

- `lib/jido/agent.ex`: public module documentation and the Zoi struct define
  one immutable value with static fields, top-level `vsn`, ID, and one state
  map.
- `lib/jido/agent.ex`: generated modules, direct definitions, instantiation,
  validation, and complete-schema functions remain public.
- `lib/jido/agent/checkpoint.ex`: checkpoint and restore use only the V3
  version-2 formats, enforce strict current definitions, and wrap custom
  payloads in a core-owned revision envelope.
- `lib/jido/agent.ex`: internal complete transition, public domain `set/2`,
  direct `cmd/3`, and custom `handle_signal/2` are implemented.
- `lib/jido/agent/validation.ex` and `lib/jido/agent/state.ex`: validation
  defines the two forms, applies the compatible revision defaults, composes
  schemas, and validates complete portable state.
- `lib/jido/agent/runner.ex`: direct and live preparation
  use the Runner, and finalization returns one candidate and Directive list.
- `lib/jido/plugin.ex:104-143,238-255,823-855`: Plugins have unique state keys,
  their schemas extend the combined state, executable writes are protected,
  and each Plugin updates its own field.
- `lib/jido/agent/builder.ex` and `lib/jido/agent/codec.ex`: Builder and Codec
  preserve `vsn`; Codec reads and writes only version 2.
- `lib/jido/portable_term.ex` and `lib/jido/persistence.ex`: recursive
  portability has bounded paths and runs at Agent state acceptance and again
  at persistence.

### Tests and examples

- `test/jido/agent_test.exs:157-390,434-576`: tests cover neutral definitions,
  instances, half-instance rejection, complete state, immutable changes,
  direct execution, and serialization.
- `test/jido/agent_test.exs:580-858`: tests cover default and custom routing,
  direct Actions and Flows, error retention, Directives, and source immutability.
- `test/jido/agent_test.exs:888-1010`: tests cover process-free lifecycle,
  direct and behavior-only restore, current module restore, custom callbacks,
  malformed checkpoints, and callback faults.
- `test/jido/agent/schema_test.exs:69-153` and
  `test/jido/plugin/contract_test.exs:584-650`: tests cover combined schema,
  root validation, Plugin-owned field protection, and one complete commit.
- `test/jido/agent/authoring_contract_test.exs:13-86`,
  `test/jido/agent/builder_test.exs:19-65`, and
  `test/jido/agent/codec_test.exs:29-67`: tests cover one authoring contract,
  route order, reusable Builders, Registry identity, and Codec errors.
- `test/jido/agent/serialization_contract_test.exs:9-52`: tests keep Agent
  authoring data separate from persistence data.
- `test/jido/persistence/checkpoint_identity_test.exs:14-32` and
  `test/jido/persistence/checkpoint_portability_test.exs:15-49`: research tests
  cover envelope identity and persistence-time portability.
- `test/jido/agent/versioning_test.exs`: focused tests cover defaults, explicit
  and invalid revisions, Builder and Codec round trips, strict definition
  equality, version-1 rejection, version-2 restore, custom envelopes, and
  module or revision mismatch.
- `test/jido/agent/portable_state_test.exs` and
  `test/jido/persistence/checkpoint_portability_test.exs`: focused tests cover
  early and defense-in-depth rejection with bounded paths for each prohibited
  term class.
- `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs`:
  the active research control proves revision-mismatch rejection.

### Current validation attempt

On 2026-09-09, `mix deps.get` resolved the locked `jido_signal` dependency
without a lockfile change. The sibling `jido_action` dependency was moved from
`main` to its required `release/v3` branch. The focused Agent, authoring,
persistence, topology-persistence, and definition-revision tests passed with
179 tests and two project-tag exclusions. The default package suite passed
with 1,102 tests and 302 project-tag exclusions. `mix quality` passed format,
warnings-as-errors compilation, strict Credo, Dialyzer, and 1,102 Jido tests
with one project-tag exclusion.

## Retained baseline

- `RB-01`: One `%Jido.Agent{}` type has a neutral definition form and an
  instance form. A half-instance is invalid.
- `RB-02`: A definition and its instances share static module, name,
  description, schema, Plugin, route, and metadata data.
- `RB-03`: An instance has a nonempty binary ID and one complete plain state
  map. The map contains domain and Plugin-owned fields.
- `RB-04`: Plugin schemas compose into the complete Agent schema. An executable
  cannot change Plugin-owned keys. A Plugin can replace only its own key.
- `RB-05`: `new/1`, generated-module `new/1`, `instantiate/2`, explicit
  validation, definition inspection, complete-schema functions, and `set/2`
  are supported. Codec owns portable definition serialization.
- `RB-06`: `set/2` deep-merges domain fields. The private transition boundary
  replaces and validates the complete combined state.
- `RB-07`: `cmd/3` evaluates without a Server. It returns a candidate and
  Directives. It does not commit or dispatch.
- `RB-08`: Direct and live paths use `Jido.Agent.Runner` for candidate
  preparation and finalization.
- `RB-09`: Custom `handle_signal/2` remains the Agent routing callback. This
  seam does not select the default route order.
- `RB-10`: Builder and Codec are supported authoring paths. Codec documents
  are separate from checkpoint data.
- `RB-11`: `checkpoint/2` and `restore/3` accept context maps and support
  complete custom module callbacks. All Agent checkpoint envelopes use
  version 2.
- `RB-12`: Default restore uses the current generated module definition when
  available. Direct and behavior-only Agents can use the embedded definition.
- `RB-13`: An Agent has no live PID, state version, timer, task, monitor, or
  runtime handle.
- `RB-14`: Agent state acceptance and persistence both reject nonportable
  terms with a bounded path.

## Gap register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `AGT-GAP-001` | `AGT-REQ-001` to `AGT-REQ-009` | Agent and validation evidence above | The two forms, constructors, and shared normalization work. | `Retain` |
| `AGT-GAP-002` | `AGT-REQ-010` to `AGT-REQ-016` | Plugin, schema, Agent state evidence, and public guide | Combined state and write protection work. The checkpoint text now states complete combined state. | `Retain`; text corrected |
| `AGT-GAP-003` | `AGT-REQ-017` to `AGT-REQ-021` | Runner and direct tests above | Direct evaluation works. Routing and error details depend on pending seams. | `Retain`; defer owner details |
| `AGT-GAP-004` | `AGT-REQ-022` to `AGT-REQ-025` | Agent, Builder, Codec, and serialization tests above | Older proposals removed supported boundaries. Current code does not. | `Remove` the removal proposals |
| `AGT-GAP-005` | `AGT-REQ-026` to `AGT-REQ-029` | Agent schema, Builder, Codec, and versioning tests | Top-level `vsn`, generated default `1`, compatible `nil`, and authoring preservation are implemented. | `Implemented; approved` |
| `AGT-GAP-006` | `AGT-REQ-030` to `AGT-REQ-035` | Agent checkpoint code and versioning tests | Strict generated definitions, version-2 reads and writes, version-1 rejection, and early revision mismatch are implemented. | `Implemented` |
| `AGT-GAP-007` | `AGT-REQ-036` to `AGT-REQ-038` | Portable-term, Agent state, and persistence tests | Agent and persistence reject all prohibited terms with bounded paths while static definitions stay valid in memory. | `Implemented; approved Agent contract` |
| `AGT-GAP-008` | `AGT-REQ-039` | Agent callback and error tests | Several callback faults still return raw tuples or arbitrary terms. | `Defer` exact shapes to seam 12 |
| `AGT-GAP-009` | All requirements | Focused tests above | No one acceptance set maps each Agent requirement to public evidence. | `Change evidence` |
| `AGT-GAP-010` | `AGT-REQ-035`, `AGT-REQ-040` | Custom callback and versioning tests | Opaque callback maps use a core-owned module and `vsn` envelope; raw payload maps are rejected. | `Implemented` |
| `AGT-GAP-011` | `AGT-REQ-032`, `AGT-REQ-036`, `AGT-REQ-041` | Direct checkpoint and portability tests | Static direct definitions remain unrestricted in memory; the embedded durable form is limited to portable maps and fails with a typed path. | `Implemented; approved` |
| `AGT-GAP-012` | `AGT-REQ-042` | Agent public API tests and Codec tests | The general Agent map function is absent. Codec owns portable definition serialization. | `Implemented; breaking V3 selection` |

## Dispositions of superseded proposals

| Earlier proposal or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| Remove the neutral definition form. | `Remove` | Two forms are public and tested. Seam 02 also needs the neutral form. |
| Add a second stored `plugin_state` field beside `state`. | `Remove` | Keep one complete state map and its tested write protection. |
| Remove `set/2` and replace the private transition API with new public state functions. | `Remove` | Current roles are clear with the combined map. No new accessor abstraction is required. |
| Run narrow Plugin preparation before route selection. | `Implemented by seams 04 and 05` | Preparation cannot change the Signal. Route choice uses the unchanged source Signal. |
| Remove custom `handle_signal/2`. | `Remove` | Custom routing is public, documented, and tested. |
| Remove Builder and Codec. | `Remove` | These are supported authoring boundaries. Checkpoint data stays separate. |
| Retain `Agent.to_map/1` as a convenience function. | `Remove` | Codec owns portable definition serialization. Checkpoints own identity and live state. |
| Replace map checkpoints with one fixed public struct. | `Remove` | A struct is not required for revision checks. Exact persistence records belong to seam 07. |
| Remove complete checkpoint and restore callbacks. | `Remove` | Current callbacks stay until an approved Plugin or persistence composition has replacement proof. |
| Restore all Agents only from a loaded generated module. | `Change in stages` | Use strict module and revision checks. Keep current V3 direct and behavior-only restore. |
| Require a positive revision for every definition. | `Change in stages` | Generated modules get a revision. Direct and behavior-only compatibility forms can stay unversioned. |
| Validate portable state at every Agent boundary without migration. | `Change after audit` | Early validation is the target, but current permissive schemas and stored state need compatibility evidence. |
| Define Agent Ref, persistence record, commit, or Agent Server state here. | `Defer` | Seams 03, 07, 06, and 08 own those contracts. |

## High-level work sequence

This sequence records the approved outcomes and completed implementation gates.
It is not a separate implementation plan.

### Phase 0 — Resolve prerequisites and Agent decisions

- Requirements: all `AGT-REQ` identifiers.
- Required outcome: approved retained model, revision rule, checkpoint rule,
  portable-state boundary, and error dependency.
- Constraints: do not decide routing, Agent Ref, Plugin facets, persistence
  records, commit, or Agent Server behavior.
- Compatibility: no runtime change.
- Verification: review each `AGT-DEC` item and all prerequisite assumptions.
- Exit criteria: the user approves or changes the Agent decisions and the
  prerequisite drafts are approved or replaced by explicit assumptions.

### Phase 1 — Lock the retained public contract

- Requirements: `AGT-REQ-001` to `AGT-REQ-025`.
- Required outcome: public docs and tests state two forms, combined state,
  direct evaluation, authoring compatibility, and current checkpoint meaning.
- Constraints: keep current function and callback behavior.
- Compatibility: no removal or deprecation.
- Verification: focused Agent, schema, Plugin contract, Builder, Codec,
  serialization, and checkpoint tests.
- Exit criteria: each retained requirement has `Proven` evidence and public
  checkpoint text states that the saved map contains complete combined state.

### Phase 2 — Add compatible Agent `vsn`

- Requirements: `AGT-REQ-026` to `AGT-REQ-029`.
- Required outcome: generated modules have a positive `vsn` and all
  authoring forms preserve it.
- Constraints: revision does not pin loaded executable code and does not define
  Agent identity or state version.
- Compatibility: existing generated modules default to `1`; direct and
  behavior-only forms can stay unversioned. Version-1 Codec documents require
  conversion before V3 decode.
- Verification: module, direct, Builder, Codec, and invalid-revision contract
  tests.
- Exit criteria: existing module source works, version-1 Codec documents are
  rejected, and every versioned normalized definition has one revision.

### Phase 3 — Enforce portable combined state

- Requirements: `AGT-REQ-036` to `AGT-REQ-038` and `AGT-REQ-041`.
- Required outcome: each Agent state acceptance point uses the approved
  path-aware portable-value and error contract.
- Constraints: validate the complete combined state and keep persistence
  validation as defense in depth.
- Compatibility: audit accepted live and stored terms before enforcement and
  publish conversion rules for rejected terms.
- Verification: direct, live, Plugin update, replacement, checkpoint, restore,
  save, and load cases for each rejected term class and exact safe paths.
- Exit criteria: no accepted candidate contains a prohibited term and every
  failure uses the approved error.

### Phase 4 — Add revision-aware checkpoint restore

- Requirements: `AGT-REQ-030` to `AGT-REQ-035` and `AGT-REQ-040`.
- Required outcome: new generated-module checkpoints carry definition revision
  and reject a mismatch before state acceptance.
- Constraints: keep combined state, plain maps, complete custom callbacks, and
  separation from persistence records.
- Compatibility: keep version-2 embedded-definition restore for direct and
  behavior-only Agents. Convert version-1 data before V3 restore.
- Verification: version-1 rejection, version-2 module and revision mismatch,
  strict static-definition check, custom callback faults, and restore tests.
- Exit criteria: new versioned checkpoints have a proved revision gate and all
  retained checkpoint fixtures still restore as specified.

### Phase 5 — Close public and downstream evidence

- Requirements: all active approved `AGT-REQ` identifiers.
- Required outcome: public docs, types, examples, and dependent seam documents
  use one approved Agent contract.
- Compatibility: no supported path is removed without a separate approved
  migration and replacement evidence.
- Verification: format, compile, focused tests, full package tests, research
  controls, and the compatible V3 package matrix.
- Exit criteria: the acceptance matrix has no `Missing` or `Conflict` item for
  an active approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `AGT-REQ-001` to `AGT-REQ-009` | `lib/jido/agent.ex:96-337`; `test/jido/agent_test.exs:157-317,434-546` | Stable public contract inventory. | `Proven` |
| `AGT-REQ-010` to `AGT-REQ-016` | `lib/jido/plugin.ex:126-143,238-255,823-855`; `test/jido/plugin/contract_test.exs:584-650` | Public wording check for combined checkpoint state. | `Proven` |
| `AGT-REQ-017` to `AGT-REQ-021` | `lib/jido/agent/runner.ex`; `test/jido/agent_test.exs` | Cross-check the approved seam-04 Turn input contract. | `Proven` |
| `AGT-REQ-022` to `AGT-REQ-025` | `lib/jido/agent.ex:259-387`; Builder, Codec, and serialization contract tests | Stable compatibility inventory. | `Proven` |
| `AGT-REQ-026` to `AGT-REQ-029` | `test/jido/agent/versioning_test.exs` | Default, explicit, invalid, direct, Builder, and Codec round trips. | `Proven` |
| `AGT-REQ-030` | `test/jido/agent/versioning_test.exs` | Mutated static data and exact normalized equality cases. | `Proven` |
| `AGT-REQ-031` and `AGT-REQ-032` | `test/jido/agent/versioning_test.exs` | Version-1 rejection fixture. | `Retired; rejection proven` |
| `AGT-REQ-033` and `AGT-REQ-034` | `test/jido/agent/versioning_test.exs` | Version-2 write, module mismatch, revision mismatch, and static-definition mismatch tests. | `Proven` |
| `AGT-REQ-035` and `AGT-REQ-040` | `test/jido/agent_test.exs`; `test/jido/agent/versioning_test.exs` | Custom envelope and raw-payload rejection. | `Proven` |
| `AGT-REQ-036` to `AGT-REQ-038`, `AGT-REQ-041` | `test/jido/agent/portable_state_test.exs`; `test/jido/persistence/checkpoint_portability_test.exs` | Early Agent checks, every rejected term class, bounded paths, direct definitions, and load defense in depth. | `Proven` |
| `AGT-REQ-039` | Shared seam-12 error normalization and callback-fault tests | None | `Proven` |
| `AGT-REQ-042` | `test/jido/agent_test.exs`; Agent Codec tests | Public API absence and portable definition serialization. | `Proven` |

## Migration and compatibility

V3 removes the earlier general `Agent.to_map/1` convenience and the core
module `new/2` constructor. Generated Agent modules keep `new/1`, and Codec is
the portable definition serialization boundary.

| Area | Compatibility rule and gate |
| --- | --- |
| Agent forms | Keep neutral definitions and instances. Use core `new/1`, generated-module `new/1`, or `instantiate/2` at the applicable boundary. |
| Combined state | Keep one map, schema composition, Plugin key protection, and complete candidate validation. |
| Public state API | Keep `set/2` and direct struct access. Keep complete transition private. Add no new accessor family in this seam. |
| Direct execution | Keep `cmd/3` and generated module delegation. Do not require a Server. |
| Routing | Keep custom `handle_signal/2`. Apply a route-order change only after seams 04 and 05 approve and prove migration. |
| Authoring | Keep DSL, direct data, Builder, and Codec. Codec is the only portable definition projection and accepts only version 2. |
| Checkpoints | Keep version-2 plain maps, direct and behavior-only embedded definitions, and custom callbacks. Reject version 1 and raw custom payloads. |
| Portable state | Keep early Agent rejection and persistence defense in depth with the reviewed code and bounded path. |
| Errors | Do not invent interim raw tuples or codes. Convert through the approved seam-12 migration. |
| Later seam values | This seam does not define Agent Ref, commit, persistence record, live result, state version, or Agent Server fields. |

## Assumptions and follow-up

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `AGT-BLK-001` | `Resolved` | 00 Overview | The shared Agent, route, `vsn`, and compatibility requirements are approved. | No further Overview action is required. |
| `AGT-BLK-002` | `Explicit assumption` | 90 Package boundaries | The current Jido ownership boundary supports this approved Agent contract. | Review the package release gate in seam 90. A conflict requires a migration. |
| `AGT-BLK-003` | `Explicit assumption` | 12 Errors and contracts | The implemented typed portability error is approved for Agent. Other callback fault normalization remains deferred. | Review the shared error matrix in seam 12. A conflict requires a migration. |
| `AGT-BLK-004` | `Resolved` | 01 Agent, 02 Agent authoring | Existing generated modules default to `vsn: 1`; direct and behavior-only definitions can stay unversioned. Seam 02 has adopted this contract. | No action. |
| `AGT-BLK-005` | `Approved implementation` | 01 Agent, 07 Persistence | A version-2 plain map supplies the `vsn` gate; no public Checkpoint struct is required. | Seam 07 must adopt this contract. |
| `AGT-BLK-006` | `Implemented` | 01 Agent, 07 Persistence | Custom maps use a V3 core envelope. Direct embedded checkpoints are limited to portable definitions. | Seam 07 must preserve the current V3 rules. |
| `AGT-BLK-007` | `Resolved for Agent` | 04 Turn evaluation, 05 Plugins | This seam preserves custom routing and Plugin-owned fields in the combined Agent state without implementing route order or the deferred Plugin model. | Seams 04 and 05 own their later implementation. |
| `AGT-BLK-008` | `Resolved for Agent` | 03 Agent identity, 08 Agent Server | The current Agent ID stays in the instance while Agent Ref and live state version remain outside this seam. | Seams 03 and 08 own those values. |

## Completion criteria

- [x] The user has approved or changed each existing `AGT-DEC` item.
- [x] Custom checkpoint `vsn` handling and direct-definition durability have
      approved implemented decisions.
- [x] Pending prerequisite drafts are explicit assumptions for this seam.
- [x] Every active approved `AGT-REQ` item has `Proven` evidence.
- [x] No unresolved `Conflict` remains in the acceptance matrix.
- [x] Both Agent forms, combined state, direct execution, Builder, Codec,
      custom routing, and checkpoint callbacks remain supported.
- [x] Agent `vsn` has Builder, Codec, default, and rejected-old-input evidence.
- [x] Version-1 rejection and version-2 checkpoint fixtures pass their stated rules.
- [x] Portable combined state is checked at every approved acceptance point and
      again at persistence.
- [x] No route, identity, Plugin facet, record, commit, or Agent Server detail is
      decided in this seam.
- [x] Public module docs and the 01 Agent documents use the approved contract.
- [x] The scoped implementation and its verification are complete.
