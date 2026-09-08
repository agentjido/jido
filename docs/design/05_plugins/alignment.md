> Seam alignment plan. This document is pending approval.

# Plugin alignment

## Status

- Design reviewed: 2026-09-08. All documents in this seam are pending approval.
- Code reviewed: `91ddd99984a0f9999d40af4ce181412ef03b757b` on branch `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md), and
  [04 Turn evaluation](../04_turn-evaluation/alignment.md). All are pending
  draft prerequisites.
- Related contracts: [02 Agent authoring](../02_agent-authoring/design.md) and
  [03 Agent identity](../03_agent-identity/design.md).
- Alignment state: `Blocked`.

The alignment state is execution status. It is not document approval. This
document defines outcomes and gates. It is not the later formal implementation
plan.

## Inputs and evidence

### Design inputs

- [Jido V3 vision](../VISION.md): a Plugin is optional lifecycle capability,
  not the required form for all customization.
- [Overview design](../00_overview/design.md): assigns four proposed facet
  owners, fixed route selection, isolated Plugin data, and coherent runtime
  replacement input.
- [Package-boundary design](../90_package-boundaries/design.md): keeps Plugins,
  adapters, authoring extensions, Directives, Telemetry, and ordinary
  composition as separate extension types.
- [Errors and contracts design](../12_errors-and-contracts/design.md): defines
  callback normalization and early portable-value checks.
- [Agent design](../01_agent/design.md): keeps one combined state map, unique
  Plugin fields, complete candidate validation, and custom checkpoints.
- [Turn-evaluation design](../04_turn-evaluation/design.md): selects one Turn
  before Plugin preparation and requires bounded Plugin inputs and
  contributions.
- [Agent-authoring design](../02_agent-authoring/design.md): preserves ordered
  Plugin declarations and encodes only static module and option data.
- [Agent-identity design](../03_agent-identity/design.md): separates Agent Ref,
  module identity, runtime handle, and state version.
- [Target design](design.md): gives this seam's recommended target.

### Canonical code

| Evidence | Canonical current behavior |
| --- | --- |
| `lib/jido/plugin.ex:1-102` | One mixed behavior owns pure preparation, live admission, outbound Signal preparation, state, Directives, dispatch, and readiness. `use Jido.Plugin` accepts no options. |
| `lib/jido/plugin.ex:104-274` | Core normalizes declarations, composes schemas, runs admission and preparation, protects state, starts optional children, and exposes a state-only runtime read. |
| `lib/jido/plugin.ex:367-670` | A declaration is a module or `{module, keyword}`. Normalization validates one private Spec and rejects duplicate modules, atom state keys, and Directive owners. |
| `lib/jido/plugin.ex:696-875` | Preparation and state updates are serial and fail fast. Preparation passes one shared Command. State reducers receive only their owned Directives and can replace one owned value. |
| `lib/jido/plugin.ex:897-978` | Runtime child Specs must be permanent. Callback raises, throws, and exits are contained, but returned arbitrary errors pass through. |
| `lib/jido/plugin/spec.ex:1-20` | The private Spec joins Agent state, Directive, dispatch, and runtime fields. There is no neutral manifest or owner Spec. |
| `lib/jido/agent/command.ex:1-74` | A preparation Command contains the complete Agent, one Signal, and one shared caller context map. |
| `lib/jido/agent/command/runner.ex:64-133` | Runner prepares Plugins before routing, then protects Plugin state, validates Directives, reduces Plugin state, and validates the complete candidate. |
| `lib/jido/agent/command/runner.ex:178-227` | Default routing requires exactly one target. A prepared Signal can change route selection. |
| `lib/jido/plugin/init.ex:1-23` | Runtime Init contains Server PID, Agent ID, module, instance, partition, and options, but no owned state or state version. |
| `lib/jido/plugin/directive_context.ex:1-32` | Post-commit context has committed Plugin state and state version plus source, effective Signal, and transient context. |
| `lib/jido/plugin/signal_context.ex:1-37` | Outbound Signal context has committed Plugin state and version, target, and bounded Turn fields. |
| `lib/jido/plugin/codec.ex:1-47` | Plugin Codec version 1 stores module and options only through a trusted Registry. It starts no runtime. |
| `lib/jido/agent_server/plugin_lifecycle.ex:8-198` | Agent Server starts, tracks, resolves, waits for, and stops optional Plugin runtimes. Runtime handles stay in private Server state. |
| `lib/jido/agent_server/plugin_child.ex:89-156` | Replacement readiness runs outside the wrapper mailbox so the new runtime can read current Agent state. The read has no matching version. |
| `lib/jido/agent_server.ex:1285-1490` | Live admission runs before shared Runner preparation. Executable work runs asynchronously after preparation. |
| `lib/jido/agent_server.ex:1493-1545` | Persistence and commit finish before Plugin Directive work starts. |
| `lib/jido/agent_server.ex:1664-1825` | Outbound preparation is reverse ordered. State-only Directives finish without dispatch. Process-free and runtime-backed dispatch use bounded tasks. |
| `lib/jido/agent.ex:370-423` | Complete custom checkpoint and restore callbacks can replace the default combined-state map. |
| `lib/jido/persistence.ex:284-316` | Persistence stores and validates a whole Agent checkpoint. It has no Plugin slice conversion or facet revision. |
| `lib/jido/plugin/scheduler.ex:1-397` | Scheduler owns `:scheduler` state, recurring and durable definitions, validation, reduction, runtime dispatch, readiness, and configuration limits. |
| `lib/jido/plugin/scheduler/occurrence.ex:1-69` | Occurrence IDs use deterministic versioned coordinates and flat Signal context metadata. |
| `lib/jido/plugin/scheduler/delivery.ex:1-85` | Delivery reads committed state, selects one pending job, creates a fresh Signal ID, and calls the Agent. |
| `lib/jido/plugin/scheduler/durable.ex:1-151` | Durable state keeps one pending occurrence, generation rules, acknowledgement, cancellation, and stale-tick rejection. |

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/plugin/contract_test.exs:424-670` | Current authoring, preparation order, typed Directives, state composition, state protection, and complete candidate validation work. |
| `test/jido/plugin/ordering_test.exs:181-313` | Ownership is unique. Admission is declaration ordered. Outbound preparation is reverse ordered. Later failure returns no partial state. |
| `test/jido/plugin/result_contract_test.exs:13-119` | Callback success, returned errors, invalid results, raises, throws, and exits have their current mixed normalization rules. |
| `test/jido/plugin/validation_test.exs:241-402` | Options, Directive declarations, state results, outbound Signals, and child faults are validated and contained. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:152-326` | Plugin handles stay outside Agent state, readiness gates startup, replacement reads fresh committed state, and runtime loss restores the last commit. |
| `test/jido/agent_server/plugin_lifecycle_test.exs:45-198` | Runtime tree ownership, startup failure, finite readiness, restart failure, and restart cleanup are covered. |
| `test/jido/plugin/scheduler/occurrence_test.exs:12-176` | Stable coordinates, distinct IDs, metadata, untracked compatibility, bounds, and portable inputs are covered. |
| `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-217` | Pending intent, retry, acknowledgement, failed writes, runtime loss, cancellation, and restore are covered. |
| `test/examples/99_research/99_09_route_selection/route_selection_test.exs:6-37` | One-route parity passes. First-match and fixed source-Signal selection are skipped target cases. |
| `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:6-34` | Current state protection passes. Declared-view and prepared-input isolation are skipped target cases. |
| `test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs:9-65` | Domain and Plugin state commit together. Invalid Plugin output preserves the prior commit and prevents dispatch. |

The superseded gap report recorded 88 focused tests with zero failures on
2026-09-08. This rewrite does not treat that record as proof for missing facet,
route, isolation, or runtime-snapshot behavior.

## Retained baseline

- `PLG-RB-001`: Agent definitions keep ordered module or module-and-keyword
  Plugin declarations.
- `PLG-RB-002`: One Plugin module can occur once in one Agent definition.
- `PLG-RB-003`: Each stateful Plugin owns one atom key in the combined Agent
  state map. Keys cannot overlap domain state or another Plugin.
- `PLG-RB-004`: Each Plugin Directive type has one owner. A Plugin cannot own a
  built-in Directive.
- `PLG-RB-005`: Preparation, admission, and state updates are serial and stop at
  the first error. Outbound Signal preparation uses reverse declaration order.
- `PLG-RB-006`: Executables cannot change Plugin-owned fields. A Plugin reducer
  receives only its owned Directives and replaces only its complete state value.
- `PLG-RB-007`: Direct evaluation runs pure Plugin work without an Agent Server.
- `PLG-RB-008`: A Plugin can have no runtime, a runtime without Directive
  dispatch, process-free dispatch, or runtime-backed dispatch.
- `PLG-RB-009`: A declared runtime root is permanent, gates readiness, and stays
  outside Agent state and checkpoints.
- `PLG-RB-010`: Plugin Directive handling starts after commit with committed
  Plugin state and state version. A later failure does not undo the commit.
- `PLG-RB-011`: A state-only Directive needs no live handler after its successful
  state reduction.
- `PLG-RB-012`: Codec stores only static Plugin module and options.
- `PLG-RB-013`: Complete custom Agent checkpoint callbacks remain supported.
- `PLG-RB-014`: Scheduler stable occurrence identity and optional durable
  pending-work recovery are supported capability behavior.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `PLG-GAP-001` | `PLG-REQ-001` to `PLG-REQ-010` | Mixed behavior and private Spec | Declaration and Codec basics work. Neutral manifests and owner Specs do not exist. | `Change, staged`; retain declaration and Codec version 1 |
| `PLG-GAP-002` | `PLG-REQ-011` to `PLG-REQ-016` | Schema composition and state protection | Current behavior meets the recommended combined-state contract. | `Retain`; move callbacks under the Agent owner |
| `PLG-GAP-003` | `PLG-REQ-017` | Persistence portability only | Plugin state and prepared input do not get early path-aware checks. | `Change` after seam-12 approval and compatibility audit |
| `PLG-GAP-004` | `PLG-REQ-018` to `PLG-REQ-022`, `PLG-REQ-027` | Agent Server and Runner order | Admission and preparation can change the Signal used for routing. | `Change` with seam 04; preserve admission order |
| `PLG-GAP-005` | `PLG-REQ-023` to `PLG-REQ-030` | Complete Command and shared context | Declared projections, owned input, and bounded transition values do not exist. | `Change`; add isolated callback values and migration delegates |
| `PLG-GAP-006` | `PLG-REQ-031` to `PLG-REQ-035` | Ordered state reduction | Fail-fast state replacement works. Plugins cannot add owned Directives. | `Retain` order and failure; `Change` contribution authority if approved |
| `PLG-GAP-007` | `PLG-REQ-036` to `PLG-REQ-042` | Directive owner, reducer, and post-commit dispatch | Most ownership and commit rules work. Paired facet validation and contributed Directives do not exist. | `Retain` current guarantees; `Change` normalization |
| `PLG-GAP-008` | `PLG-REQ-043` to `PLG-REQ-052` | Init, lifecycle, and dispatch contexts | Lifecycle works, but Init has no coherent state and version pair. | `Retain` lifecycle; `Change` bootstrap and facet boundary |
| `PLG-GAP-009` | `PLG-REQ-053` to `PLG-REQ-058` | Whole-Agent checkpoint only | No Persistence facet, revision, or owned-slice conversion exists. | `Defer implementation` until checkpoint compatibility is approved |
| `PLG-GAP-010` | `PLG-REQ-059` and `PLG-REQ-060` | No Topology Plugin code | No bounded pure Topology facet exists. | `Defer` until the static owner seam is ready |
| `PLG-GAP-011` | `PLG-REQ-061` to `PLG-REQ-076` | Scheduler modules and tests | The recommended occurrence and durable delivery contract is substantially implemented. | `Retain`; require parity through facet migration |
| `PLG-GAP-012` | All requirements | Current callback errors use `term()` and several raw values | Approved stable codes, uniform normalization, and exact public facet values are missing. | `Change` with seam 12 and public API review |

## Dispositions of superseded claims

This table retains each distinct useful claim from the removed Plugin drafts.
Git history keeps the removed text.

| Superseded claim or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| `Jido.Plugin` is both the only public configuration struct and the callback behavior. | `Remove` the struct claim and `Replace` the mixed behavior. | Current code has no `%Jido.Plugin{}` struct. The target uses one manifest module and owner facets. |
| Keep all pure and live callbacks in one behavior. | `Replace`. | Agent and Agent Server have different data, timing, and failure owners. |
| Store Plugin data in a separate `Agent.plugin_state` map. | `Remove`. | Seam 01 keeps one tested combined Agent state map. |
| Give each declaration an atom-or-string instance ID separate from its module. | `Remove for the first contract`. | Current module identity keeps Directive and runtime lookup unambiguous. Dynamic multiple instances remain deferred. |
| Keep at most one declaration for each package module. | `Retain`. | Current normalization already rejects duplicates. |
| Add declared top-level Agent observations. | `Retain target`. | It gives the Agent facet a bounded read contract. |
| Pass one complete Agent Command through all Plugins. | `Replace`. | Each facet gets a bounded view and one separately owned input. |
| Route after Plugin preparation. | `Replace`. | Seam 04 selects one executable from the source Signal first. |
| Use exact public names `Plugin.Command`, `Context`, `Transition`, and `Contribution`. | `Defer exact names`; retain value roles. | Owner namespaces and API review must avoid new naming conflicts. |
| Rename `update_state/3` to `reduce_directives/3`. | `Replace recommendation` with a bounded contribution callback. | The approved target can include unchanged state and added owned Directives. Exact callback name remains open. |
| Let a contribution replace Plugin state and add owned Directives. | `Retain target`. | Ownership and append order are explicit in `PLG-REQ-032` to `PLG-REQ-034`. |
| Remove live admission and outbound Signal preparation. | `Remove the removal proposal`. | Both are supported. Move them to the Agent Server facet. |
| Rename live `dispatch/4` to `handle_directive/4`. | `Defer exact name`; retain the narrower meaning. | The public API naming review owns the final callback name. |
| Require every live Plugin Directive to have a handler. | `Clarify`. | Successful state-only reduction is complete handling when no live handler is declared. |
| Allow Directive dispatch with no runtime process. | `Retain`. | Current code and tests use the same bounded task contract. |
| Fall back to process-free dispatch when a declared runtime is missing. | `Reject`. | A missing required runtime remains an error. |
| Put committed owned state and matching version in runtime Init. | `Retain target`. | Current state-pull recovery proves fresh state but not one coherent pair. |
| Put runtime handles in Plugin configuration or Agent state. | `Reject`. | Agent Server owns runtime-only data. |
| Use Agent Ref in direct Plugin context. | `Reject`. | Direct evaluation has no required instance namespace. Live identity fields wait for seams 03 and 09. |
| Add a pure Persistence facet for one state slice. | `Retain target with gate`. | It cannot run until custom checkpoint composition is approved. |
| Let Persistence Plugins wrap adapter reads or writes. | `Reject`. | Persistence and the adapter keep storage and commit authority. |
| Add whole-record encryption or compression to the Plugin facet. | `Defer to a separate codec design`. | Whole-record framing is not one Plugin state slice. |
| Change custom Agent callbacks to domain-state conversion now. | `Defer`; use compatibility bypass first. | Existing complete callbacks are public and tested. |
| Add a pure Topology facet for canonical entries. | `Retain target`. | It must add no process or live reconciliation authority. |
| Let a Topology facet add arbitrary live resource kinds. | `Reject for the first contract`. | Activation and rollback stay with the Topology owner. |
| Treat Agent and Topology authoring extensions as Plugin facets. | `Reject`. | They remain static syntax lowering under their authoring owners. |
| Permit several facet modules for one owner. | `Defer`. | The first manifest permits one module per owner. |
| Permit dynamic Plugin installation in a live Agent. | `Defer`. | Static schema and ownership must stay coherent in the first contract. |
| Run Agent-level Plugin callbacks concurrently. | `Defer`. | Declaration order and fail-fast behavior remain the observable contract. |
| Make Scheduler durable work a general Directive replay guarantee. | `Reject`. | Recovery is capability-owned saved intent and acknowledgement. |
| Change occurrence identity to Agent Ref during facet migration. | `Reject for this migration`. | Existing version-1 IDs must remain stable. |
| Claim exactly-once Scheduler business effects. | `Reject`. | External work can repeat before acknowledgement. |
| Retain Scheduler generation, reserved metadata, one-pending-item policy, retry, acknowledgement, and clock limits. | `Retain`. | These are implemented, tested, and useful unique contracts. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the formal plan only after the user approves this seam.

### Phase 0 — Resolve prerequisites and Plugin decisions

- Requirements: all `PLG-REQ` identifiers.
- Required outcome: approved facet, state, isolation, contribution, runtime,
  checkpoint, naming, and Scheduler decisions.
- Constraints: pending prerequisite requirements remain assumptions.
- Compatibility: no runtime change.
- Verification: review all `PLG-DEC` items against gaps and dispositions.
- Exit criteria: the user approves or changes the decisions and owner conflicts
  are resolved.

### Phase 1 — Lock current behavior and normalized ownership

- Requirements: `PLG-REQ-001` to `PLG-REQ-016`, `PLG-REQ-036` to
  `PLG-REQ-046`, and `PLG-REQ-051` to `PLG-REQ-052`.
- Required outcome: current declarations and legacy callbacks normalize to one
  neutral manifest and isolated owner Specs.
- Constraints: keep current declaration sites, combined state, order,
  state-only Directives, process-free dispatch, and Codec version 1.
- Compatibility: explicit callback-to-owner classification; no silent guess.
- Verification: characterization tests and owner-Spec field checks.
- Exit criteria: legacy and manifest declarations produce equivalent ownership
  data without changing runtime behavior.

### Phase 2 — Establish bounded Agent facet evaluation

- Requirements: `PLG-REQ-017` to `PLG-REQ-037`.
- Required outcome: fixed selection, declared projections, owned preparation,
  bounded contribution, portable values, and stable order.
- Constraints: direct use needs no Server. Keep complete candidate validation.
- Compatibility: delegates preserve old `prepare/2` and `update_state/3` until
  each Plugin migrates.
- Verification: source-Signal, route, isolation, owned input, state, Directive,
  first-error, and direct/live parity tests.
- Exit criteria: no Agent facet can read or replace foreign Turn data.

### Phase 3 — Establish Agent Server facet and coherent runtime input

- Requirements: `PLG-REQ-018` to `PLG-REQ-021`, `PLG-REQ-038` to
  `PLG-REQ-052`.
- Required outcome: bounded admission, outbound preparation, Directive
  handling, lifecycle, readiness, and one state-version bootstrap pair.
- Constraints: Agent Server owns tasks, timeouts, commit order, restart, and
  errors. Plugin runtime state stays outside the Agent.
- Compatibility: keep current runtime state-pull API during migration.
- Verification: process-free and process-backed dispatch, state-only handling,
  initial start, replacement, readiness, runtime loss, and post-commit tests.
- Exit criteria: every replacement runtime gets one matching committed view.

### Phase 4 — Add optional Persistence facet

- Requirements: `PLG-REQ-053` to `PLG-REQ-058`.
- Required outcome: pure owned-slice dump and load with explicit revision data.
- Constraints: preserve the byte adapter and persistence-owner commit rules.
- Compatibility: complete custom checkpoints bypass the facet in the first
  stage. Default checkpoints remain readable.
- Verification: slice isolation, format revision, portability, schema,
  no-adapter-call-on-error, and no-runtime-on-load-error tests.
- Exit criteria: one Plugin can migrate only its owned value and cannot affect
  storage meaning.

### Phase 5 — Add optional Topology facet

- Requirements: `PLG-REQ-059` and `PLG-REQ-060`.
- Required outcome: pure bounded contributions to canonical Topology data.
- Constraints: no new live resource kind or reconciliation authority.
- Compatibility: authoring extensions, Builder, and Codec stay separate.
- Verification: authoring parity, duplicate ownership, plan limits, and
  no-process or I/O tests.
- Exit criteria: a facet changes static meaning only through the Topology owner.

### Phase 6 — Migrate built-ins and close release evidence

- Requirements: all requirements, with `PLG-REQ-061` to `PLG-REQ-076` as the
  Scheduler parity set.
- Required outcome: built-ins and a public-only package use owner facets while
  supported behavior remains available.
- Constraints: do not remove legacy detection before the approved support
  period and compatible package proof.
- Compatibility: Scheduler occurrence IDs and checkpoint fixtures remain
  stable.
- Verification: full Plugin, Agent Server, Scheduler, persistence, example,
  public-only, package, compile, lint, docs, and coverage checks.
- Exit criteria: the acceptance matrix has no `Missing`, `Partial`, or
  `Conflict` entry for an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `PLG-REQ-001`, `PLG-REQ-003`, `PLG-REQ-007` | Declaration and ordering tests | Keep declarations equal through manifest normalization. | `Proven` for current behavior |
| `PLG-REQ-002`, `PLG-REQ-004` to `PLG-REQ-006` | One mixed private Spec | Neutral manifest, option mapping, facet count, and foreign-field tests. | `Missing` |
| `PLG-REQ-008` | Direct no-Plugin Agent tests | Keep after evaluator changes. | `Proven` |
| `PLG-REQ-009`, `PLG-REQ-010` | Plugin Codec version 1 | Manifest and facet-revision compatibility fixtures. | `Proven` for current form; target is partial |
| `PLG-REQ-011` to `PLG-REQ-016` | Schema, ownership, reducer, and candidate tests | Run unchanged through Agent facet migration. | `Proven` |
| `PLG-REQ-017` | Persistence checks some portable values | Early Plugin state and prepared-input checks with bounded paths. | `Partial` |
| `PLG-REQ-018` to `PLG-REQ-022`, `PLG-REQ-027` | Admission is ordered, but prepared Signal selects route | Source-Signal route and admission-authority matrix. | `Conflict` |
| `PLG-REQ-023` to `PLG-REQ-030` | Complete Command and skipped isolation cases | Public callback values, projection allowlist, and cross-Plugin denial tests. | `Missing` |
| `PLG-REQ-031`, `PLG-REQ-032`, `PLG-REQ-035` | Ordered fail-fast state reduction | Keep first-error and no-candidate proof. | `Proven` for current state contribution |
| `PLG-REQ-033`, `PLG-REQ-034` | Plugins cannot add Directives | Owned addition and exact append-order tests. | `Missing` |
| `PLG-REQ-036`, `PLG-REQ-037` | Unique ownership and validation tests | Keep through facet normalization. | `Proven` |
| `PLG-REQ-038` | State-only Directives finish after commit without dispatch | Keep explicit live acceptance proof. | `Proven` |
| `PLG-REQ-039` | One mixed Spec owns declaration and dispatch | Paired Agent and Server facet validation. | `Partial` |
| `PLG-REQ-040` to `PLG-REQ-042` | Agent Server commit and Directive tests | Keep process-free, runtime, failure, and version proof. | `Proven` |
| `PLG-REQ-043` to `PLG-REQ-046`, `PLG-REQ-049` | Runtime and lifecycle tests | Keep after owner split. | `Proven` |
| `PLG-REQ-047`, `PLG-REQ-048` | Runtime can read fresh state, not a version pair | Initial and replacement state-version snapshot tests. | `Missing` |
| `PLG-REQ-050` | Scheduler runtime delivers through Agent calls | Public Signal-reentry test for each state-changing runtime. | `Proven` for Scheduler |
| `PLG-REQ-051`, `PLG-REQ-052` | Reverse order and validation tests | Keep with bounded facet context. | `Proven` for current behavior |
| `PLG-REQ-053` to `PLG-REQ-058` | Whole-Agent checkpoint only | Owned-slice, revision, portability, bypass, and failure-order tests. | `Missing` |
| `PLG-REQ-059`, `PLG-REQ-060` | No Topology facet | Pure canonical contribution tests. | `Missing` |
| `PLG-REQ-061` to `PLG-REQ-068` | Scheduler occurrence tests | Keep exact fixtures and IDs through migration. | `Proven` |
| `PLG-REQ-069` to `PLG-REQ-076` | Durable and recovery tests | Keep enqueue, pending, skip, restore, acknowledgement, stale-tick, interval, and duplicate proof. | `Proven` |
| All requirements | Current callback errors and no public facet fixture | Seam-12 code assertions and a public-only package fixture. | `Partial` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Declarations | Keep modules and `{module, keyword}` pairs in the same order. A package manifest must not require declaration-site changes. |
| Mixed behavior | Detect each known legacy callback with an explicit callback-to-owner table. Keep legacy support for the approved beta or minor-release period. |
| Plugin state | Keep atom top-level fields in the combined Agent state map. Do not add `Agent.plugin_state` in this migration. |
| Prepared input | Old callbacks can use a compatibility delegate. New bounded inputs must not be exposed to a legacy Plugin as false isolation. |
| Route order | Change source-Signal selection and Plugin callback compatibility together. Do not run a Plugin that depends on route rewriting under the new order without a clear migration error. |
| Contributions | Adapt `update_state/3` to unchanged-or-owned-state output. Only new callbacks can add owned Directives until parity is proved. |
| Live callbacks | Preserve admission and reverse outbound preparation. Move ownership without changing current order or failure timing. |
| Directive dispatch | Keep state-only handling, process-free dispatch, required-runtime errors, post-commit order, and current timeout policy. |
| Runtime Init | Add state and version. Keep `Jido.Plugin.state/2` during migration. Do not reuse an old Init after a replacement. |
| Checkpoints | Keep combined state, version-1 default reads, and complete custom callbacks. A custom callback bypasses Persistence facets in the first stage. |
| Codec | Keep version-1 module-and-options documents readable. Add facet revision data only with an explicit new format and Registry fixtures. |
| Scheduler | Keep existing occurrence IDs, context keys, untracked definitions, option meanings, pending state, and recovery fixtures. |
| Built-ins | Migrate one capability shape at a time: Agent-only, Server-only, process-free handler, paired runtime, then Scheduler and Sensor Manager. |
| Rollback | A release that reads a new manifest or facet revision must have an old-code rejection or conversion rule. It must not silently drop Plugin state or pending Scheduler work. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `PLG-BLK-001` | `Blocker` | 00 Overview | Four facet owners, Plugin isolation, and runtime replacement input are pending approval. | Approve or replace the related Overview decisions. |
| `PLG-BLK-002` | `Blocker` | 90 Package boundaries | Plugin, adapter, authoring, Directive, and Telemetry separation is pending approval. | Approve or change the extension boundary. |
| `PLG-BLK-003` | `Blocker` | 12 Errors and contracts | Callback codes, fault normalization, and portable paths are pending approval. | Approve before final public callback types and early checks. |
| `PLG-BLK-004` | `Blocker` | 01 Agent | Combined state, custom checkpoints, and portable-state timing are pending approval. | Approve or change the Agent contract. |
| `PLG-BLK-005` | `Blocker` | 04 Turn evaluation | Source-Signal first-match routing and bounded contribution inputs are pending approval. | Approve route order and parity boundary. |
| `PLG-BLK-006` | `Assumption` | 02 Agent authoring | All authoring forms preserve ordered package declarations and static options. | Keep `AUTH-REQ-004`, `AUTH-REQ-036`, and `AUTH-REQ-049` aligned. |
| `PLG-BLK-007` | `Blocker` | 03 Agent identity, 08 Agent Server, 09 Jido instance | Exact live runtime identity fields are not approved. | Define whether target Init carries Agent Ref beside compatibility fields. |
| `PLG-BLK-008` | `Blocker` | 05 Plugins, 07 Persistence | Complete custom checkpoints and owned-slice conversion have no approved long-term composition. | Approve compatibility bypass and decide the later domain-only callback path. |
| `PLG-BLK-009` | `Blocker` | 08 Agent Server, 10 Runtime topology | No current API supplies committed Plugin state and matching version in one value. | Approve bootstrap value, commit-race behavior, and replacement ownership. |
| `PLG-BLK-010` | `Assumption` | 11 Topology control plane | A first Topology facet lowers only to current canonical static values. | Confirm size, key, dependency, and duplicate-owner limits. |
| `PLG-BLK-011` | `Assumption` | 05 Plugins | Scheduler version-1 occurrence identity must remain stable through facet migration. | Approve `PLG-DEC-010`; use a new version for any later Ref-based scope. |
| `PLG-BLK-012` | `Blocker` | 05 Plugins | Exact public facet behavior, callback, and callback-value names remain open. | Complete API naming review before implementation planning. |
| `PLG-BLK-013` | `Blocker` | Design index and dependent seams | Files outside this task still reference removed Plugin drafts, and the review table does not list the new standard files. | Update those owner-scoped documents after this seam is accepted. |

## Completion criteria

- [ ] The user has approved or changed every `PLG-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `PLG-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains.
- [ ] One declaration normalizes to owner Specs with no foreign fields.
- [ ] Direct Agent use needs only the Agent facet.
- [ ] Plugin state, prepared input, projections, and Directives pass ownership
      and portability tests.
- [ ] Every runtime start and replacement receives matching committed state and
      version.
- [ ] Persistence and Topology facets cannot obtain runtime, storage, commit, or
      live-control authority.
- [ ] Scheduler occurrence and recovery tests keep their current ID and
      durability meaning.
- [ ] A public-only external Plugin package passes the approved contract.
- [ ] Supported legacy behavior remains until the migration gate passes.
- [ ] After approval, a formal implementation plan is created separately.
