> Seam alignment plan. This document is pending approval.

# Agent alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `4a19f562` on branch `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md), and
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md), all used
  as pending draft prerequisites.
- Alignment state: `Draft`.

The alignment state is execution status. It is not document approval.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): keeps direct Agent use, all supported
  authoring forms, explicit values, and developer-owned application structure.
- [Overview design](../00_overview/design.md): supplies pending requirements
  for two Agent roles, direct evaluation, definition revision, state write
  ownership, and compatibility.
- [Package-boundary design](../90_package-boundaries/design.md): keeps Jido as
  the Agent owner above public `jido_action` and `jido_signal` contracts.
- [Errors and contracts design](../12_errors-and-contracts/design.md): supplies
  pending error, protocol-control, and portable-value rules.
- [Target design](design.md): defines the recommended Agent target.

### Canonical code

- `lib/jido/agent.ex:1-135`: public module documentation and the Zoi struct
  define one immutable value with static fields, ID, and one state map.
- `lib/jido/agent.ex:137-368`: generated modules, direct definitions,
  instantiation, validation, complete schema, and `to_map/1` are public.
- `lib/jido/agent.ex:370-423,521-598`: checkpoint and restore use plain maps,
  custom callbacks, current module definitions, and embedded definitions.
- `lib/jido/agent.ex:439-477`: internal complete transition, public domain
  `set/2`, direct `cmd/3`, and custom `handle_signal/2` are implemented.
- `lib/jido/agent/validation.ex:10-22,60-99,137-205,303-307`: validation
  defines the two forms, limits instance overrides, composes schemas, applies
  defaults, and validates complete state.
- `lib/jido/agent/command/runner.ex:29-93,120-133`: direct and live preparation
  use the Runner, and finalization returns one candidate and Directive list.
- `lib/jido/plugin.ex:104-143,238-255,823-855`: Plugins have unique state keys,
  their schemas extend the combined state, executable writes are protected,
  and each Plugin updates its own field.
- `lib/jido/agent/builder.ex:31-126` and `lib/jido/agent/codec.ex:29-99`:
  Builder and Codec are supported definition and instance boundaries.
- `lib/jido/portable_term.ex:1-24` and `lib/jido/persistence.ex:284-315`:
  recursive portability is checked at persistence, but not at Agent state
  acceptance and not with a path.

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
  root validation, Plugin state write protection, and one complete commit.
- `test/jido/agent/authoring_contract_test.exs:13-86`,
  `test/jido/agent/builder_test.exs:19-65`, and
  `test/jido/agent/codec_test.exs:29-67`: tests cover one authoring contract,
  route order, reusable Builders, Registry identity, and Codec errors.
- `test/jido/agent/serialization_contract_test.exs:9-52`: tests keep Agent
  authoring data separate from persistence data.
- `test/jido/persistence/checkpoint_identity_test.exs:14-32` and
  `test/jido/persistence/checkpoint_portability_test.exs:15-49`: research tests
  cover envelope identity and persistence-time portability.
- `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:16-27`:
  current restore works, but revision-mismatch rejection is not implemented.

## Retained baseline

- `RB-01`: One `%Jido.Agent{}` type has a neutral definition form and an
  instance form. A half-instance is invalid.
- `RB-02`: A definition and its instances share static module, name,
  description, schema, Plugin, route, and metadata data.
- `RB-03`: An instance has a nonempty binary ID and one complete plain state
  map. The map contains domain and Plugin-owned state.
- `RB-04`: Plugin schemas compose into the complete Agent schema. An executable
  cannot change Plugin-owned keys. A Plugin can replace only its own key.
- `RB-05`: `new/1`, `new/2`, `instantiate/2`, explicit validation, definition
  inspection, complete-schema functions, `to_map/1`, and `set/2` are supported.
- `RB-06`: `set/2` deep-merges domain fields. The private transition boundary
  replaces and validates the complete combined state.
- `RB-07`: `cmd/3` evaluates without a Server. It returns a candidate and
  Directives. It does not commit or dispatch.
- `RB-08`: Direct and live paths use `Jido.Agent.Command.Runner` for candidate
  preparation and finalization.
- `RB-09`: Custom `handle_signal/2` remains the Agent routing callback. This
  seam does not select the default route order.
- `RB-10`: Builder and Codec are supported authoring paths. Codec documents
  are separate from checkpoint data.
- `RB-11`: `checkpoint/2` and `restore/3` accept context maps and support
  complete custom module callbacks. The default version-1 checkpoint is a map.
- `RB-12`: Default restore uses the current generated module definition when
  available. Direct and behavior-only Agents can use the embedded definition.
- `RB-13`: An Agent has no live PID, state version, timer, task, monitor, or
  runtime handle.
- `RB-14`: Persistence checks complete records for portable terms. Agent
  construction and transition do not yet make this check.

## Gap register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `AGT-GAP-001` | `AGT-REQ-001` to `AGT-REQ-009` | Agent and validation evidence above | The two forms, constructors, and shared normalization work. | `Retain` |
| `AGT-GAP-002` | `AGT-REQ-010` to `AGT-REQ-016` | Plugin, schema, and Agent state evidence above | Combined state and write protection work. Public docs call one checkpoint domain-only. | `Retain`; correct contract text |
| `AGT-GAP-003` | `AGT-REQ-017` to `AGT-REQ-021` | Runner and direct tests above | Direct evaluation works. Routing and error details depend on pending seams. | `Retain`; defer owner details |
| `AGT-GAP-004` | `AGT-REQ-022` to `AGT-REQ-025` | Agent, Builder, Codec, and serialization tests above | Older proposals removed supported boundaries. Current code does not. | `Remove` the removal proposals |
| `AGT-GAP-005` | `AGT-REQ-026` to `AGT-REQ-029` | Agent schema and definition-revision research test | There is no definition revision field or authoring-format support. | `Change, staged` |
| `AGT-GAP-006` | `AGT-REQ-030` to `AGT-REQ-035` | Agent checkpoint code and tests above | Version 1 and callbacks work. There is no strict static-definition check or revision-aware default format. | `Change, compatible` |
| `AGT-GAP-007` | `AGT-REQ-036` to `AGT-REQ-038` | Portable-term and persistence evidence above | Portability runs only at persistence, gives no path, and accepts non-byte-aligned bitstrings. | `Change` after audit and seam-12 approval; exclude static definition terms |
| `AGT-GAP-008` | `AGT-REQ-039` | Agent callback and error tests | Several callback faults still return raw tuples or arbitrary terms. | `Defer` exact shapes to seam 12 |
| `AGT-GAP-009` | All requirements | Focused tests above | No one acceptance set maps each Agent requirement to public evidence. | `Change evidence` |

## Dispositions of superseded proposals

| Earlier proposal or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| Remove the neutral definition form. | `Remove` | Two forms are public and tested. Seam 02 also needs the neutral form. |
| Split Plugin state into a new `plugin_state` field. | `Remove` | This seam keeps the combined map and its tested write protection. Seam 05 can propose a later reviewed migration. |
| Remove `set/2` and replace the private transition API with new public state functions. | `Remove` | Current roles are clear with the combined map. No new accessor abstraction is required. |
| Select the first route before Plugin preparation. | `Defer` | Route choice and preparation order belong to seams 04 and 05. The pending Overview draft is not approval. |
| Remove custom `handle_signal/2`. | `Remove` | Custom routing is public, documented, and tested. |
| Remove Builder, Codec, and `to_map/1`. | `Remove` | These are supported compatibility boundaries. Checkpoint data stays separate. |
| Replace map checkpoints with one fixed public struct. | `Remove` | A struct is not required for revision checks. Exact persistence records belong to seam 07. |
| Remove complete checkpoint and restore callbacks. | `Remove` | Current callbacks stay until an approved Plugin or persistence composition has replacement proof. |
| Restore all Agents only from a loaded generated module. | `Change in stages` | Use strict module and revision checks for the new generated-module format. Keep version-1, direct, and behavior-only restore. |
| Require a positive revision for every definition. | `Change in stages` | Generated modules get a revision. Direct and behavior-only compatibility forms can stay unversioned. |
| Validate portable state at every Agent boundary without migration. | `Change after audit` | Early validation is the target, but current permissive schemas and stored state need compatibility evidence. |
| Define Agent Ref, persistence record, commit, or Agent Server state here. | `Defer` | Seams 03, 07, 06, and 08 own those contracts. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the implementation plan later with `ce-plan` after design approval.

### Phase 0 — Resolve prerequisites and Agent decisions

- Requirements: all `AGT-REQ` identifiers.
- Required outcome: approved retained model, revision rule, checkpoint rule,
  portable-state boundary, and error dependency.
- Constraints: do not decide routing, Agent Ref, Plugin facets, persistence
  records, commit, or Agent Server behavior.
- Compatibility: no runtime change.
- Verification: review each `AGT-DEC` item and all prerequisite blockers.
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
- Exit criteria: each retained requirement has `Proven` evidence and no public
  text calls the combined checkpoint state domain-only.

### Phase 2 — Add compatible definition revision

- Requirements: `AGT-REQ-026` to `AGT-REQ-029`.
- Required outcome: generated modules have a positive revision and all
  authoring forms preserve it.
- Constraints: revision does not pin loaded executable code and does not define
  Agent identity or state version.
- Compatibility: existing generated modules default to `1`; direct and
  behavior-only forms can stay unversioned; old Codec documents still decode.
- Verification: module, direct, Builder, Codec, `to_map/1`, and invalid-revision
  contract tests.
- Exit criteria: existing module source and version-1 Codec documents work,
  and every versioned normalized definition has one revision.

### Phase 3 — Enforce portable combined state

- Requirements: `AGT-REQ-036` to `AGT-REQ-039`.
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

- Requirements: `AGT-REQ-030` to `AGT-REQ-035`.
- Required outcome: new generated-module checkpoints carry definition revision
  and reject a mismatch before state acceptance.
- Constraints: keep combined state, plain maps, complete custom callbacks, and
  separation from persistence records.
- Compatibility: read version 1; keep embedded-definition restore for direct
  and behavior-only Agents; do not rewrite stored data in place.
- Verification: version-1 fixtures, version-2 module and revision mismatch,
  strict static-definition check, custom callback faults, and restore tests.
- Exit criteria: new versioned checkpoints have a proved revision gate and all
  retained checkpoint fixtures still restore as specified.

### Phase 5 — Close public and downstream evidence

- Requirements: all approved `AGT-REQ` identifiers.
- Required outcome: public docs, types, examples, and dependent seam documents
  use one approved Agent contract.
- Compatibility: no supported path is removed without a separate approved
  migration and replacement evidence.
- Verification: format, compile, focused tests, full package tests, research
  controls, and the compatible V3 package matrix.
- Exit criteria: the acceptance matrix has no `Missing` or `Conflict` item for
  an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `AGT-REQ-001` to `AGT-REQ-009` | `lib/jido/agent.ex:96-337`; `test/jido/agent_test.exs:157-317,434-546` | Stable public contract inventory. | `Proven` |
| `AGT-REQ-010` to `AGT-REQ-016` | `lib/jido/plugin.ex:126-143,238-255,823-855`; `test/jido/plugin/contract_test.exs:584-650` | Public wording check for combined checkpoint state. | `Proven` |
| `AGT-REQ-017` to `AGT-REQ-021` | `lib/jido/agent/command/runner.ex:29-133`; `test/jido/agent_test.exs:341-369,718-858` | Cross-check the approved seam-04 Turn input contract. | `Proven` |
| `AGT-REQ-022` to `AGT-REQ-025` | `lib/jido/agent.ex:259-387`; Builder, Codec, and serialization contract tests | Stable compatibility inventory. | `Proven` |
| `AGT-REQ-026` to `AGT-REQ-029` | `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:16-27` | Default, explicit, invalid, direct, Builder, Codec, and map round trips. | `Missing` |
| `AGT-REQ-030` | No strict static-definition checkpoint check exists. | Mutated static data and exact normalized equality cases. | `Missing` |
| `AGT-REQ-031` and `AGT-REQ-032` | `lib/jido/agent.ex:403-423,563-598`; `test/jido/agent_test.exs:888-976` | Versioned fixtures that lock current read behavior. | `Proven` |
| `AGT-REQ-033` and `AGT-REQ-034` | No revision-aware default checkpoint exists. | Version-2 write, module mismatch, revision mismatch, and static-definition mismatch tests. | `Missing` |
| `AGT-REQ-035` | `test/jido/agent_test.exs:937-952,978-1010` | Compatibility test with the approved new default format. | `Proven` |
| `AGT-REQ-036` to `AGT-REQ-038` | Persistence research tests reject PIDs and improper lists. | Early Agent checks, bitstring cases, exact paths, and save/load defense-in-depth tests. | `Partial` |
| `AGT-REQ-039` | Current validation and routing errors are typed; callback faults vary. | Seam-12 normalization matrix for every Agent public failure. | `Partial` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Agent forms | Keep neutral definitions, instances, and their current constructors. |
| Combined state | Keep one map, schema composition, Plugin key protection, and complete candidate validation. |
| Public state API | Keep `set/2` and direct struct access. Keep complete transition private. Add no new accessor family in this seam. |
| Direct execution | Keep `cmd/3` and generated module delegation. Do not require a Server. |
| Routing | Keep custom `handle_signal/2`. Apply a route-order change only after seams 04 and 05 approve and prove migration. |
| Authoring | Keep DSL, direct data, Builder, Codec, `to_map/1`, and current version-1 Codec decode. Add revision without removing a form. |
| Checkpoints | Keep plain maps, version-1 reads, direct and behavior-only embedded definitions, and custom callbacks. Add version 2 only for the approved revision path. |
| Portable state | Audit current values first. Keep persistence checks. Add early rejection with the approved code and path. |
| Errors | Do not invent interim raw tuples or codes. Convert through the approved seam-12 migration. |
| Later seam values | This seam does not define Agent Ref, commit, persistence record, live result, state version, or Agent Server fields. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `AGT-BLK-001` | `Blocker` | 00 Overview | The shared Agent, route, revision, and compatibility requirements are pending approval. | Approve them or replace them with explicit Agent-seam assumptions. |
| `AGT-BLK-002` | `Blocker` | 90 Package boundaries | Package ownership and public compatibility gates are pending approval. | Approve or change the package boundary. |
| `AGT-BLK-003` | `Blocker` | 12 Errors and contracts | The error taxonomy, portable path, and normalization rules are pending approval. | Approve them before early portability or error conversion. |
| `AGT-BLK-004` | `Assumption` | 01 Agent, 02 Agent authoring | Existing generated modules can default to revision `1`; direct and behavior-only definitions can stay unversioned. | Approve or change `AGT-DEC-002`. |
| `AGT-BLK-005` | `Assumption` | 01 Agent, 07 Persistence | A version-2 plain map is enough for the revision gate; no public Checkpoint struct is required. | Approve or change `AGT-DEC-004`. |
| `AGT-BLK-006` | `Blocker` | 01 Agent, 07 Persistence | The exact version-2 fields, version-1 read period, and mixed-version rollback rule are not approved. | Approve the checkpoint migration before implementation. |
| `AGT-BLK-007` | `Assumption` | 04 Turn evaluation, 05 Plugins | This seam can preserve custom routing and combined Plugin state without selecting route order or Plugin facets. | Confirm these inputs in the owner seams. |
| `AGT-BLK-008` | `Assumption` | 03 Agent identity, 08 Agent Server | The current Agent ID stays in the instance while Ref and live state version remain outside this seam. | Confirm in the owner seams. |

## Completion criteria

- [ ] The user has approved or changed each `AGT-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `AGT-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains in the acceptance matrix.
- [ ] Both Agent forms, combined state, direct execution, Builder, Codec,
      custom routing, and checkpoint callbacks remain supported.
- [ ] Definition revision has Builder, Codec, default, and old-input evidence.
- [ ] Version-1 and new-format checkpoint fixtures pass their stated rules.
- [ ] Portable combined state is checked at every approved acceptance point and
      again at persistence.
- [ ] No route, identity, Plugin facet, record, commit, or Agent Server detail is
      decided in this seam.
- [ ] Public module docs and dependent seam documents use the approved contract.
- [ ] After approval, `ce-plan` creates the formal implementation plan.
