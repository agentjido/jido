> Approved seam alignment. Dependent owner-seam follow-up remains open.

# Agent authoring alignment

## Status

- Design reviewed and approved: 2026-09-09.
- Code reviewed: `ae559f4f41318d0021f8044589f99da810f4f82e` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md), and
  [01 Agent](../01_agent/alignment.md). Overview, Agent, and errors are
  approved. Package boundaries remain an explicit pending assumption.
- Alignment state: `Approved; scoped implementation complete`.

The review-status table in `docs/design/README.md` is the source of truth for
document approval.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): requires supported authoring forms to produce
  one normalized Agent definition and keeps developer composition explicit.
- [Overview design](../00_overview/design.md): keeps DSL, direct data, Builder,
  Codec, neutral definitions, and authoring extensions during migration.
- [Package-boundary design](../90_package-boundaries/design.md): keeps static
  authoring extensions separate from Plugins and runtime hooks.
- [Errors and contracts design](../12_errors-and-contracts/design.md): supplies
  pending authoring failure and bang-function rules.
- [Agent design](../01_agent/design.md): owns the two Agent forms and the
  approved compatible Agent `vsn` contract.
- [Target design](design.md): defines the approved authoring target.

### Canonical code

| Evidence path | Canonical current behavior |
| --- | --- |
| `lib/jido/agent.ex:48-84,137-247` | `use Jido.Agent` installs Spark, inline Actions, module accessors, constructors, direct `cmd/3`, and persistence callbacks. |
| `lib/jido/agent.ex:182-188,259-307` | `agent/0` uses the canonical constructor. Direct definitions and module instances have separate public entries. |
| `lib/jido/agent/validation.ex` | One definition key set and constructor normalize static data, preserve `vsn`, compose Plugins, normalize routes, and limit instance overrides. |
| `lib/jido/agent/authoring.ex:28-79,107-110` | Route forms use `defaults`. Explicit defaults require a plain map. The legacy target tuple accepts any map, including a struct. |
| `lib/jido/agent/dsl/compiler.ex:7-71,104-108` | The compiler combines forms, lowers extensions, records private interface metadata, generates functions, and verifies the canonical definition after compile. |
| `lib/jido/agent/dsl/compiler.ex:145-278` | Interface compilation checks exact routes, uniqueness, Signal source, argument order, schema fields, and function conflicts. |
| `lib/jido/agent/dsl/macros.ex:27-71,104-135` | A route has one named or extension target, or one inline Action. Inline syntax compiles through `Jido.Action.Inline`. |
| `lib/jido/agent/dsl/generator.ex:4-29,81-159` | Generated helpers have docs and types for tagged Signal, bang Signal, and live-call roles. |
| `lib/jido/agent/interface.ex:8-71` | Runtime packaging separates payload, Signal envelope, caller context, and timeout options. |
| `lib/jido/agent/builder.ex` | Builder module input starts from canonical `agent/0`; staged input preserves `vsn`, order, and first error; all public entries have specs. |
| `lib/jido/agent/codec.ex` | Codec writes version 2 with `vsn`, reads version 1, derives a neutral definition from definitions or instances, and encodes no live state. |
| `lib/jido/agent/codec.ex:103-147` | Route records store `defaults` and Registry identifiers. Codec keeps the legacy struct-default tuple form on decode. |
| `lib/jido/agent/codec/data.ex:6-59,61-170` | Closed tagged data rejects runtime values and checks depth, node, collection, and string limits. |
| `lib/jido/agent/codec/registry.ex` | Registry validates typed entries, unique values, and direct aliases. Route predicates must be external unary captures. Its public entries have specs. |
| `lib/jido/plugin/codec.ex` | Plugin Codec stores canonical module and options through the same Registry, excludes runtime data, and has public specs. |
| `lib/jido/agent/extension.ex` | Documented `lower/3` runs pure lowerers in declaration order and returns ordinary core Agent authoring data. |

### Tests and examples

| Evidence path | Behavior proved or specified |
| --- | --- |
| `test/jido/agent/authoring_test.exs:286-350` | One requirement-mapped suite proves strict definition and instance parity for direct map, direct keyword, keyword-only module, Spark-block module, staged Builder, module Builder, and trusted JSON Codec forms. It covers schema, metadata, `vsn`, two ordered Plugins, ordered Action and Flow routes, defaults, priority, stable Registry identifiers, common-data exclusions, and canonical `agent/0` input. |
| `test/jido/agent/authoring_test.exs:353-438` | Direct and live execution agree. Inline route Actions become reusable ordinary Actions. Codec contains no interface, Signal-source, or inline-source fields. |
| `test/jido/agent/authoring_test.exs:439-571` | Generated helpers preserve omitted and explicit values, publish docs and types, reject ambiguous input, and leave executable validation to execution. |
| `test/jido/agent/authoring_test.exs:572-663` | External predicates round-trip; Plugin Codec and aliases work; instance encoding does not parse live state; valid local closures fail only at Codec. |
| `test/jido/agent/authoring_test.exs:664-915` | Codec limits, closed data, direct route forms, compile diagnostics, `params` rejection, Plugin-label rejection, and later-module verification are covered. |
| `test/jido/agent/authoring_contract_test.exs:13-56` | Public boundaries have distinct duplicate policies and preserve the route-default compatibility exception. |
| `test/jido/agent/builder_test.exs:19-80` | Builder target checks, declaration order, reuse, and first-error retention are covered. |
| `test/jido/agent/codec_test.exs:29-76` | Codec round-trips all accepted default forms and stops at the first target error. |
| `test/jido/agent/authoring_extension_test.exs:114-310` | Spark extension order, target claims, public data lowering into direct, Builder, and Codec forms, common validation, and error cases are covered. |
| `test/jido/agent/serialization_contract_test.exs:9-43` | Agent authoring JSON and persistence records use separate namespaces and formats. |
| `test/jido/agent/versioning_test.exs:31-85` | Generated defaults, explicit and invalid `vsn`, direct compatibility, Builder, Codec version 2, and Codec version-1 reads are covered. |
| `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs` | Revision mismatch is an active passing control after seam-01 work. |
| `test/examples/01_basic/README.md:1-18` | The Basic suite has five fixtures and 16 tests. It does not contain five cross-form parity tests. |

### Validation record

The superseded gap analysis recorded these results on 2026-09-08:

- Focused authoring, Builder, Codec, Registry, validation, and extension
  suites: 64 tests passed.
- Basic examples with the example tag: 16 tests passed.

The final 2026-09-09 seam-02 checks produced these results:

- Primary authoring and extension files: 38 tests passed.
- Mapped authoring, Builder, Codec, Registry, validation, serialization,
  extension, and versioning set: 77 tests passed.
- Compile with warnings as errors: passed.
- Full default suite: 1,110 tests passed and 302 tests were excluded by the
  standard tags.
- Example suite: 284 tests passed and 10 tests were skipped. All 10 skips are
  in the research examples and name deferred work.
- Repository quality alias: format passed, compile passed with warnings as
  errors, Credo reported no issues, Dialyzer reported no errors or skips, and
  1,110 tests passed with one standard exclusion.

A skipped test is not passing evidence.

## Retained baseline

- `AUTH-RB-001`: Module, Spark, direct map and keyword, Builder, and Codec forms
  are supported and end at Agent validation.
- `AUTH-RB-002`: Neutral definitions and instances are separate. Authoring
  Codec data does not store ID or state.
- `AUTH-RB-003`: Spark can declare schema, metadata, ordered Plugins, ordered
  routes, inline Actions, Signal source, and explicit interfaces.
- `AUTH-RB-004`: `agent/0` is the canonical module definition.
  `__agent_config__/0` can contain pre-normalized compiler data.
- `AUTH-RB-005`: Inline Actions compile to normal `jido_action` Action modules.
  `route_action/1` makes the target reusable.
- `AUTH-RB-006`: Generated interfaces package input and delegate. They do not
  perform Plugin preparation or executable validation.
- `AUTH-RB-007`: Builder preserves route order and its first error. It does not
  execute Actions. Module input reads canonical `agent/0` data.
- `AUTH-RB-008`: Codec uses a closed JSON-compatible format and trusted typed
  Registry. Stored strings cannot create atoms or modules.
- `AUTH-RB-009`: Direct and Builder routes can use valid runtime predicates.
  Registry accepts only external unary captures for route predicates.
- `AUTH-RB-010`: Explicit route defaults require a plain map. A legacy target
  tuple accepts map structs, and Codec preserves this form.
- `AUTH-RB-011`: Agent extensions lower Spark entities in declaration order to
  ordinary Agent configuration. Builder and Codec have no extension-entity
  input. `Jido.Agent.Extension.lower/3` is the public pure data entry.
- `AUTH-RB-012`: Definitions and Builder data preserve Agent `vsn`. Codec writes
  version 2 with `vsn` and reads version 1 with the approved compatibility rule.
- `AUTH-RB-013`: Custom domain helpers remain ordinary Elixir functions.
  `define` is an explicit request for standard generated route helpers.
- `AUTH-RB-014`: Codec instance input derives and validates the neutral
  definition. It does not parse or encode live identity or state.

## Gap register

The dispositions below are approved for this seam.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `AUTH-GAP-001` | `AUTH-REQ-001` to `AUTH-REQ-008` | Agent validation and the mapped parity matrix | All common forms converge at the canonical definition for keyword-only and Spark-block fixtures. | `Implemented`; retain the contract |
| `AUTH-GAP-002` | `AUTH-REQ-009` to `AUTH-REQ-015` | Agent module, compiler, versioning, and parity evidence | `agent/0` is canonical; private compiler data stays internal; approved Agent `vsn` rules are present. | `Implemented`; retain module authority |
| `AUTH-GAP-003` | `AUTH-REQ-016` to `AUTH-REQ-020` | Inline macro and reuse tests | Inline Action behavior is implemented through the public `jido_action` contract. | `Implemented`; retain without a version claim |
| `AUTH-GAP-004` | `AUTH-REQ-021` to `AUTH-REQ-034` | Compiler, generator, interface, and exclusion evidence | Generated interfaces are module-only API and are absent from canonical and Codec data. | `Implemented`; retain the explicit exclusion |
| `AUTH-GAP-005` | `AUTH-REQ-035` to `AUTH-REQ-039`, `AUTH-REQ-061` | Builder, versioning, specs, and parity tests | Builder reads `agent/0`, preserves `vsn`, order, first errors, and public specs. | `Implemented` |
| `AUTH-GAP-006` | `AUTH-REQ-040` to `AUTH-REQ-049`, `AUTH-REQ-062` | Codec, Registry, versioning, portability, and state-transform tests | Version 2 preserves `vsn`; version 1 is compatible; instance encoding is definition-first; local closures stay valid but are not encodable. | `Implemented, compatible` |
| `AUTH-GAP-007` | `AUTH-REQ-050` to `AUTH-REQ-054` | Extension docs, specs, Spark tests, and data parity test | One public pure lowerer feeds direct, Builder, and Codec authoring without storing source entities. | `Implemented` |
| `AUTH-GAP-008` | `AUTH-REQ-055` | Compiler and recompilation test above | Later-module verification is implemented. | `Implemented`; retain |
| `AUTH-GAP-009` | `AUTH-REQ-056` | Authoring functions return structured errors and public types are complete for the seam entries | Final stable codes and callback normalization depend on pending seam 12. | `Defer` exact error shape to seam 12 |
| `AUTH-GAP-010` | All requirements | Requirement-mapped keyword-only and Spark-block parity matrix | Schema, metadata, `vsn`, ordered Plugins and routes, Action, Flow, defaults, priority, trusted Registry, definitions, and instances are covered. | `Implemented` |

## Dispositions of superseded material

| Earlier material or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| Use only versioned Agent modules and remove Builder, Codec, Registry, direct data, and neutral definitions. | `Remove` as a target. | The APIs are public and tested. Approved `OVR-REQ-063`, `AGT-REQ-022` to `AGT-REQ-024`, and this seam preserve them. Package release proof remains with `PKG-REQ-034`. |
| Make every Agent definition module-owned and versioned. | `Change in stages`. | Approved seam 01 requires revisions for generated modules and permits unversioned direct and behavior-only definitions. |
| Require static-definition equality at persistent creation and exact module and revision checks at restore. | `Defer` to seams 01 and 07. | This seam preserves revision through authoring but does not define checkpoint or persistence policy. |
| Make `__agent_config__/0` the normalized public authority. | `Remove`. | `agent/0` performs canonical construction. The double-underscore functions remain private compiler metadata. |
| Treat generated interfaces as parity across all forms. | `Remove`. | Interface functions are module API. Definition parity is the common boundary. |
| Add extension declarations to Builder and Codec. | `Remove`. | A public pure lowerer gives data users access without storing Spark entities. |
| Reject all local route closures in common Agent validation. | `Remove`. | Direct custom routing remains supported. Codec reports that an unregistered value is not encodable. |
| Remove the legacy route-default struct exception immediately. | `Remove`. | Tests preserve it. Any removal needs a separate deprecation and replacement proof. |
| Encode only neutral definitions and reject instances. | `Remove`. | Current public examples and tests encode instances. Definition-first encoding keeps that input compatible. |
| Generate startup functions on every Agent module. | `Defer` to seam 09 and retain no new target here. | Jido instance and Agent Server seams own startup. |
| Remove explicit domain helpers. | `Remove`. | Applications can keep ordinary Elixir helpers. Generated helpers exist only when `define` is present. |
| Add portable named-function executable targets in this seam. | `Defer` to `jido_action`. | Executable resolution, validation, results, and telemetry need one lower-layer owner. |
| Claim that a definition revision pins loaded Action or Flow code. | `Remove`. | The approved Overview says that Agent `vsn` does not pin loaded Action or Flow code. |
| Use `Jido.Agent` as the name of both core Agent and a downstream package abstraction. | `Remove`. | `Jido.Agent` is the current core value and macro. Downstream wrappers must use an unambiguous application module name. |
| State that five Basic fixtures have 15 tests and five parity tests. | `Correct`. | The Basic index has 16 runtime tests. Cross-form parity is one focused matrix with two module-source fixtures. |
| Link to the deleted Agent DSL migration report. | `Remove`. | Current code and tests are the canonical evidence. |
| Attribute interface inspiration to Ash code interfaces. | `Retain as rationale only`. | Explicit names and input mapping informed the design. Jido uses Spark directly and has no Ash dependency. |

## High-level work sequence

This sequence records the approved outcomes and completed implementation gates.
It is not a separate implementation plan.

### Phase 0 — Resolve prerequisites and authoring decisions

- Requirements: all `AUTH-REQ` identifiers.
- Required outcome: approved form retention, parity boundary, module authority,
  Codec input rule, portable subset, extension rule, and revision dependency.
- Constraints: do not decide Agent fields, route selection, checkpoint restore,
  Plugin runtime, or Agent Server behavior.
- Compatibility: no runtime change.
- Verification: review all `AUTH-DEC` items and prerequisite blockers.
- Exit criteria: the user approves or changes each decision, and prerequisite
  drafts are approved or replaced by explicit assumptions.

### Phase 1 — Lock the retained authoring contract

- Requirements: `AUTH-REQ-001` to `AUTH-REQ-040`, `AUTH-REQ-049` to
  `AUTH-REQ-052`, `AUTH-REQ-055`, and `AUTH-REQ-057` to `AUTH-REQ-061`.
- Required outcome: public docs and tests state all supported forms, canonical
  parity, Spark and inline contracts, generated interfaces, Builder behavior,
  Codec separation, and extension validation.
- Constraints: preserve route and Plugin order and do not execute runtime work
  during authoring.
- Compatibility: no removal or deprecation.
- Verification: compile diagnostics, function docs and types, Builder, Codec,
  Registry, extension, Action, Flow, direct/live, and example tests.
- Exit criteria: every retained requirement has current or newly added passing
  evidence.

### Phase 2 — Align definition revision

- Requirements: `AUTH-REQ-014`, `AUTH-REQ-015`, `AUTH-REQ-039`, and
  `AUTH-REQ-048`.
- Required outcome: each applicable module, direct value, Builder, map, and
  Codec path preserves the approved Agent-seam revision.
- Constraints: revision does not define checkpoint, restore, state-version, or
  executable-code policy.
- Compatibility: existing module source and version-1 Codec documents follow
  the approved seam-01 migration rule.
- Verification: default, explicit, invalid, Builder, map, Codec version, and
  round-trip tests.
- Exit criteria: all applicable canonical definitions have the expected
  revision and old input behaves as approved.

### Phase 3 — Make Codec input and portability explicit

- Requirements: `AUTH-REQ-041` to `AUTH-REQ-047` and `AUTH-REQ-062`.
- Required outcome: definition-first instance encoding and a tested
  Registry-resolvable static subset.
- Constraints: preserve instance calls, direct runtime predicates, closed
  tagged data, document limits, and trusted resolution.
- Compatibility: an instance continues to encode the same static document.
  A local closure remains valid outside Codec.
- Verification: non-idempotent state schema, definition equality, local and
  external predicates, missing identifiers, aliases, duplicate keys, hostile
  documents, and limits.
- Exit criteria: instance state cannot change static encoding, and every
  non-encodable valid definition gets the approved authoring error.

### Phase 4 — Publish the data extension boundary and complete types

- Requirements: `AUTH-REQ-033`, `AUTH-REQ-034`, `AUTH-REQ-039`,
  `AUTH-REQ-053`, `AUTH-REQ-054`, and `AUTH-REQ-056`.
- Required outcome: one documented pure lowerer and complete public types for
  Builder, Codec, Registry, and extension entries.
- Constraints: no runtime work, no stored Spark entities, and no interim error
  model outside seam 12.
- Compatibility: current Spark extension modules and lowered output remain
  valid.
- Verification: public docs and type checks, data-lowering parity, order,
  target claims, invalid results, and canonical validation tests.
- Exit criteria: a data author can lower extension input and then use direct,
  Builder, or Codec authoring without private functions.

### Phase 5 — Close downstream and release evidence

- Requirements: all approved `AUTH-REQ` identifiers.
- Required outcome: examples and dependent seams use the approved parity,
  revision, and extension contracts.
- Compatibility: no supported authoring API is removed without a separate
  approved staged migration.
- Verification: format, compile, focused tests, full package tests, Basic
  examples, public-only extension fixture, and compatible V3 package matrix.
- Exit criteria: the acceptance matrix has no `Missing` or `Conflict` state for
  an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `AUTH-REQ-001` to `AUTH-REQ-008` | Agent validation, authoring contracts, and two-fixture parity matrix | Keep the mapped matrix in the core suite. | `Proven` |
| `AUTH-REQ-009` to `AUTH-REQ-013` | Agent macro, DSL compiler, compile diagnostics, and canonical module parity | Keep private metadata out of public data. | `Proven` |
| `AUTH-REQ-014` and `AUTH-REQ-015` | Versioning and parity tests | Keep default, explicit, invalid, direct, and behavior-only cases. | `Proven` |
| `AUTH-REQ-016` to `AUTH-REQ-020` | Inline macro and reuse tests | Cross-package inline Action compatibility against release `jido_action` | `Proven` in current workspace |
| `AUTH-REQ-021` to `AUTH-REQ-034` | Compiler, generator, interface, docs, types, packaging, and diagnostic tests | Public API inventory and approved seam-12 error cases | `Proven` for current interface behavior |
| `AUTH-REQ-035` to `AUTH-REQ-039`, `AUTH-REQ-061` | Builder code, public specs, target checks, versioning, and parity tests | Keep no-execution and first-error cases. | `Proven` |
| `AUTH-REQ-040` | Serialization contract test | Keep authoring, checkpoint, and persistence format separation after revision work | `Proven` |
| `AUTH-REQ-041`, `AUTH-REQ-042`, `AUTH-REQ-062` | Definition-first instance test with a non-idempotent state transform and static-field exclusions | Keep generated and trusted Registry paths. | `Proven` |
| `AUTH-REQ-043` to `AUTH-REQ-047` | Codec, Data, Registry, alias, hostile-input, limit, and local-closure tests | Apply final seam-12 error code after approval. | `Proven` for behavior; shared code is deferred |
| `AUTH-REQ-048` | Versioning and parity tests | Keep version-2 round trip and version-1 generated and direct fixtures. | `Proven` |
| `AUTH-REQ-049` | Plugin Codec tests | Preserve through Agent Codec version change | `Proven` |
| `AUTH-REQ-050` to `AUTH-REQ-052` | Extension host, Spark fixture, and public data-entry tests | Keep order, claims, invalid-result, and common-validation cases. | `Proven` |
| `AUTH-REQ-053` and `AUTH-REQ-054` | Public `lower/3` docs and spec plus direct, Builder, and Codec parity | Keep source entities out of Codec data. | `Proven` |
| `AUTH-REQ-055` | After-verify compiler path and later-module test | Preserve in compatible package set | `Proven` |
| `AUTH-REQ-056` | Structured authoring, tagged and bang paths, and seam-12 stable codes | None | `Proven` |
| `AUTH-REQ-057` to `AUTH-REQ-060` | Generated constructor, packaging, docs, and direct/live tests | Preserve in the public interface acceptance set | `Proven` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Forms | Keep module, Spark, direct map and keyword, Builder, Codec, and neutral definitions. |
| Module metadata | Keep double-underscore compiler functions private. Use `agent/0` for canonical data. |
| Revision | Keep the implemented seam-01 `vsn` rules without removing an old input. Keep version-1 Codec reads. |
| Inline Actions | Keep current syntax and `route_action/1`. Test against the intended `jido_action` release source. |
| Interfaces | Keep generated names, arities, docs, types, packaging, and live delegation. Interface functions remain module-only. |
| Builder | Keep the first-error and order rules. Module input reads `agent/0`; public fields and functions keep their specs. |
| Codec instances | Keep instance input and static definition-first encoding. Do not parse or encode live ID or state. |
| Route predicates | Keep valid direct predicates. Codec requires trusted Registry identifiers and external unary captures. |
| Route defaults | Keep explicit plain maps and the legacy tuple map-struct exception. Any unification needs separate deprecation. |
| Extensions | Keep Spark host behavior and public pure `lower/3`. Do not store extension entities in Codec data. |
| Errors | Adopt approved seam-12 codes by boundary. Do not expose private compiler or Registry data in error output. |
| Cross-package versions | Do not name a stale `jido_action` version. Test the declared release-compatible package set. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `AUTH-BLK-001` | `Resolved` | 00 Overview | Shared form retention, revision, and compatibility requirements are approved. | No further Overview action is required for seam 02. |
| `AUTH-BLK-002` | `Explicit assumption` | 90 Package boundaries | The current package ownership and extension categories support this approved authoring contract. | Review the package release gate in seam 90. A conflict requires a migration. |
| `AUTH-BLK-003` | `Explicit assumption` | 12 Errors and contracts | Current structured authoring errors support this approved contract. Final shared codes remain deferred to seam 12. | Review the shared error matrix. A conflict requires a migration. |
| `AUTH-BLK-004` | `Resolved` | 01 Agent | The definition-revision field, generated default, direct compatibility, and old-document rule are approved and implemented. | Keep seam-02 evidence aligned with seam 01. |
| `AUTH-BLK-005` | `Approved implementation` | 02 Agent authoring | Parity applies to canonical definitions, not module functions or source syntax. | No action. |
| `AUTH-BLK-006` | `Approved implementation` | 02 Agent authoring | Codec keeps instance input and uses definition-first static encoding. | No action. |
| `AUTH-BLK-007` | `Approved authoring contract` | 02 Agent authoring and `jido_signal` | Direct Router predicates can exceed the Codec portable subset. | Confirm the release-compatible `jido_signal` package retains the required predicate behavior. |
| `AUTH-BLK-008` | `Approved implementation` | 02 Agent authoring | Data extensions lower before Builder or Codec and do not enter documents. | No action. |
| `AUTH-BLK-009` | `Resolved for authoring` | 04 Turn evaluation and `jido_action` | The approved Overview says Agent `vsn` does not pin loaded Action or Flow code. | Seam 04 retains the V3 non-guarantee. |

## Completion criteria

- [x] The user has approved or changed each `AUTH-DEC` item.
- [x] Package-boundary and shared-error prerequisites are approved or retained
      as explicit assumptions.
- [x] No unresolved seam-02 implementation conflict remains in the acceptance
      matrix. Shared error codes remain a deferred owner condition.
- [x] All supported forms produce equal canonical definitions for equivalent
      source data.
- [x] Module-only interfaces and source-only extension syntax are not described
      as canonical Agent data.
- [x] Definition revision passes module, direct, Builder, map, and Codec cases
      required by seam 01.
- [x] Codec instance input, portable subset, Registry safety, and document
      limits have passing evidence.
- [x] Public Builder, Codec, Registry, generated-interface, and extension docs
      and types match the approved seam contract.
- [x] No checkpoint, restore, route-selection, Plugin-runtime, commit, Agent
      Server, or identity contract is decided in this seam.
- [ ] Dependent seams use the approved definition and parity contract.
