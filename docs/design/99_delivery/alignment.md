> Seam alignment plan. This document is pending approval.

# Delivery alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `86017bd57bfe99e47d035400839fcf857ef71d8a` on
  branch `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md) through
  [13 Observability](../13_observability/alignment.md), plus
  [90 Package boundaries](../90_package-boundaries/alignment.md). All are used
  as pending draft prerequisites.
- Alignment state: `Blocked` on release-scope approval and a compatible package
  set.
- Executed during this review: `mix test test/examples/99_research --only
  example --seed 0` returned 34 passes and 11 skips on 2026-09-08.

The alignment state is execution status. It is not document approval. This is
a high-level alignment record, not an implementation task plan.

## Inputs and evidence

### Design

- [Design index](../README.md): the review-status table is the approval source.
- [Overview](../00_overview/design.md): shared scope, compatibility, and target
  contracts.
- [Package boundaries](../90_package-boundaries/design.md): package ownership,
  public-only use, and compatible-set requirements.
- [Owner seam alignments](../00_overview/alignment.md): current, partial,
  missing, conflict, and blocked evidence from the full dependency chain.
- [Delivery design](design.md): proposed release and evidence contract.

### Canonical configuration and package metadata

- [`mix.exs`](../../../mix.exs): declares Jido `3.0.0-beta.1`, Elixir `~> 1.18`,
  a local `jido_action` dependency, Hex `jido_signal ~> 3.0.0-beta.4`, a
  90-percent coverage threshold, package contents, docs, and quality aliases.
- [CI workflow](../../../.github/workflows/ci.yml): runs core tests and docs and
  validates the Hex package for main-bound work. It does not state one full
  release gate for examples, benchmarks, coverage, or the ecosystem matrix.
- [`coveralls.json`](../../../coveralls.json): excludes examples, tests, and
  dependencies and sets the minimum coverage to 90 percent.
- Sibling manifests: `jido_action` is `3.0.0-beta.8` on `release/v3`;
  `jido_signal` is `3.0.0-beta.4` on `release/v3`; Jido AI is version `2.3.0`
  with local V3 paths; Jido Browser is version `2.4.0` with V2 Jido ranges.

### Public docs, tests, and examples

- [README](../../../README.md): calls the branch an unpublished beta candidate
  and says release checks are incomplete.
- [Testing guide](../../../guides/testing.md): defines the core, benchmark, and
  example suites, the 90-percent coverage gate, 11 allowed research skips, and
  the separate `DIST-03` skip.
- [Migration guide](../../../guides/migration.md) and
  [API migration map](../../../guides/api-migration-map.md): define current V2
  porting guidance. They say V2 and V3 writers must not share storage keys.
- [`test/test_helper.exs`](../../../test/test_helper.exs): default tests exclude
  example, benchmark, flaky, and skip tags.
- [Research tests](../../../test/examples/99_research/README.md): 45 executable
  tests. The current focused result is 34 passes and 11 skips. The skips cover
  route selection, Plugin isolation, Plugin runtime Init, stable identity,
  definition revision, durable deletion, active-Turn revision, state migration,
  and live Topology update.
- [`DIST-03`](../../../test/jido/agent_server/distributed_authority_test.exs):
  cluster-exclusive ownership is an approved current skip, not implemented
  behavior.
- Saved feature, live-upgrade, and core-refinement result documents named by
  the old delivery files no longer exist. Executable tests and current
  automation are the canonical evidence.

### Point-in-time evidence limits

- [`2026-09-07-agent-refinement.md`](../../../docs/performance/2026-09-07-agent-refinement.md)
  records past passes for quality, 93.6-percent core coverage, benchmarks,
  Elixir 1.18.5 and OTP 27, docs, and Hex build. Later focused fixes also passed
  quality, docs, and package checks.
- Those results do not name the current candidate commit and do not prove this
  delivery design. They are `Partial` historical evidence only.
- The current worktree had a pre-existing change in
  `examples/04_runtime/04_09_agent_observation/event_probe.ex` during this
  review. This alignment does not treat the worktree as a clean release input.

## Retained baseline

- Keep code, public module docs, executable tests, and current automation as
  canonical evidence.
- Keep `mix quality` as the core quality command. Keep docs, package, coverage,
  benchmarks, examples, runtime floor, and package-matrix checks as separate
  release gates.
- Keep current supported V3 APIs until an owner seam approves and proves a
  staged change.
- Keep research assertions in the repository. A deferred assertion can remain
  skipped with its identifier and reason.
- Keep cluster-exclusive ownership outside current core claims.
- Keep Jido core local and keep distributed control-plane policy outside core.
- Keep V2 migration documentation, but do not claim automatic stored-data
  compatibility or downgrade.

## Gap register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `DEL-GAP-001` | `DEL-REQ-001` to `DEL-REQ-004` | All seam documents are pending; no release-role record exists. | Scope and authority are not selected. | `Blocked`: user approval and named owners are required. |
| `DEL-GAP-002` | `DEL-REQ-005` to `DEL-REQ-009` | Current manifests use one local path, one Hex beta, one V3-path AI package, and one V2 Browser package. | No publishable compatible set is proved. | `Change`: select and test one exact set. |
| `DEL-GAP-003` | `DEL-REQ-010` to `DEL-REQ-020` | Quality configuration is current; broad pass records are historical. | No complete record is bound to the current candidate. | `Change`: run final gates after scope and implementation close. |
| `DEL-GAP-004` | `DEL-REQ-021` to `DEL-REQ-024` | 11 research tests and `DIST-03` are skipped with reasons. | The scope ledger does not classify them. | `Change`: bind each skip to a required, deferred, or excluded contract. |
| `DEL-GAP-005` | `DEL-REQ-025` to `DEL-REQ-028` | Public guides exist, but the migration guide names `jido_action` beta.7 while the local package is beta.8. Old result links are stale. | Candidate docs are not one checked set. | `Change`: run a version and claim consistency gate. |
| `DEL-GAP-006` | `DEL-REQ-029` to `DEL-REQ-033` | Owner seams recommend additive compatibility; no one dated support register exists. | Deprecation and removal gates are not selected. | `Change`: create one compatibility register. |
| `DEL-GAP-007` | `DEL-REQ-034` to `DEL-REQ-039` | V2 porting guidance exists. Upgrade research has skipped assertions and seven earlier ideas without probes. | Upgrade, downgrade, and rollback claims are not selected or proved. | `Defer or change`: approve a narrow claim and test it. |
| `DEL-GAP-008` | `DEL-REQ-040` to `DEL-REQ-042` | Old delivery files included detailed task order. | Alignment and implementation planning were mixed. | `Change`: keep only high-level gates here; use `ce-plan` after approval. |

## Superseded delivery claim dispositions

The four removed delivery documents were pending drafts. The table preserves
their useful intent and gives every claim group a current disposition.

| Superseded claim group | Disposition | Current owner or evidence |
| --- | --- | --- |
| Delivery is only retained planning history. | `Replace`: delivery now owns release gates and evidence, not subsystem behavior. | `DEL-REQ-001` to `DEL-REQ-042` |
| The old ten-step implementation sequence is the active order. | `Remove`: it was deferred and conflicted with current APIs. Keep only the high-level sequence below. | Later `ce-plan` work |
| Add exact public Ref, Checkpoint, Commit, Record, Status, Transition, Contribution, and runtime structs first. | `Defer exact shapes`: value roles stay with owner seams and seam 12. | 01, 03, 05 to 09, 12 |
| Apply recursive portability at every proposed boundary. | `Retain target, pending`: current persistence checks are partial; owner seams define acceptance points and errors. | 01, 05, 07, 12 |
| Use only module authoring and remove neutral definitions, Builder, and Codec. | `Remove`: current and target seams retain these supported forms. | 01 and 02 |
| Replace the Plugin contract immediately with isolated preparation, Transition values, contribution rules, and new runtime hosts. | `Stage`: retain isolation and owned-state intent, but use the seam-05 facet migration and compatibility gates. | 04, 05, 08, 10 |
| Select the route before Plugin preparation and choose the first Router match. | `Retain target, missing`: the current Runner prepares first and rejects multiple matches. | 04 and 05; two skipped FA-01 tests |
| Make a Ref-first facade the only live API and make PID-based Agent Server calls private. | `Remove immediate restriction`: add Ref-first behavior before any approved deprecation. | 03, 08, 09, 12 |
| Add one Turn timeout, evaluation cancellation, stale-result checks, and a closed error policy in one Server step. | `Split by owner`: keep useful limit and cancellation targets; preserve current policies until 08 and 12 approve migration. | 08 and 12 |
| Write an initial record, stop after every write error, use tombstones, and prove explicit durable work. | `Retain target, pending`: initial record, authority loss, and tombstone rules are missing; Scheduler proves one capability pattern only. | 06, 07, 08 |
| Start Plugin runtimes in a separate pool with fresh committed state and version. | `Retain state/version target; defer physical pool`: current topology stays until failure proof supports a move. | 05, 08, 09, 10 |
| Remove logical child ownership and generic child Directives from core. | `Remove`: current target seams retain owned children and explicit known-node placement. | 08, 10, 90 |
| Remove debug and old observation paths when semantic telemetry is added. | `Remove immediate removal`: keep old paths until inventory, parity, notice, and approval. | 13 |
| The old Agent, route, Plugin, Server, persistence, topology, error, and observation bullet lists are release proof. | `Replace`: they remain useful acceptance intent, but owner requirements and current executable tests define proof. | Owner seam acceptance matrices; `DEL-REQ-019` |
| Future Builder, durable, cluster, transport, and audit packages are available delivery targets. | `Defer`: capability names are proposals until their package owner provides public API and evidence. | 90 and future package owners |
| The planning baseline's supported runtime list is an immutable V3 guarantee. | `Retain only canonical current facts`: current support stays until an approved migration; the old snapshot is not release proof. | Code, public docs, tests |
| The 11 research gaps are regressions or automatic release blockers. | `Classify`: they are missing proposed contracts. Only approved release-required contracts block. | `DEL-REQ-021` to `DEL-REQ-024` |
| The proposed Plugin facet order can proceed before the custom-checkpoint rule. | `Block`: approve checkpoint and Persistence-facet composition first. | 01, 05, 07 |
| The planning baseline's eight-step order is the active implementation plan. | `Remove`: use prerequisite alignment gates, then create a separate plan after approval. | High-level sequence below |
| Saved branch names, dependency commits, and pass counts prove the release. | `Retain as historical only`: final evidence must name the exact candidate and matrix. | `DEL-REQ-009`, `DEL-REQ-019`, `DEL-REQ-020` |
| The V3 design-change tables are normative removal instructions. | `Remove normative force`: their retained directions are assigned above; conflicting removals are rejected. | Current seam designs |
| The old gap analysis's ordered gate recommendations are the final release plan. | `Replace`: retain scope, traceability, public fixture, package matrix, and fresh checks as requirements, not tasks. | This design |
| Deleted feature, upgrade, and refinement result files are current evidence. | `Remove`: the files are absent. Use executable tests, automation, and commit-specific records. | `DEL-REQ-028` |
| Live Agent and Topology upgrade must ship in V3. | `Defer by recommendation`: add them only if the approved scope changes. | Overview, 04, 08, 11 |
| Ordinary Directives or Action I/O have automatic rollback or exactly-once delivery. | `Reject`: external I/O is not rolled back; recoverable work needs an explicit capability. | 06; `DEL-REQ-039` |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create detailed implementation plans with `ce-plan` only after user approval.

### Phase 0 — Approve delivery authority and scope

- Requirements: `DEL-REQ-001` to `DEL-REQ-004`.
- Required outcome: named owners and one scope ledger for all prerequisite
  requirements and current skips.
- Verification: user approval recorded in the design review index and the
  release record.
- Exit criteria: every target contract and skip has one release status.

### Phase 1 — Close required owner-seam gaps

- Requirements: the prerequisite requirements marked `required`.
- Required outcome: each owner seam changes its acceptance state to `Proven`.
- Constraints: retain supported APIs until the compatibility register permits
  a staged change.
- Verification: owner-seam tests and current canonical evidence.
- Exit criteria: no required item is `Missing`, `Conflict`, or `Blocked`.

### Phase 2 — Select and prove the package set

- Requirements: `DEL-REQ-005` to `DEL-REQ-009`.
- Required outcome: publishable sources and public-only integration for every
  package in the release claim.
- Verification: dependency tree, source audit, consumer compile, and runtime
  integration tests.
- Exit criteria: one immutable package matrix passes.

### Phase 3 — Close compatibility and migration

- Requirements: `DEL-REQ-025` to `DEL-REQ-039`.
- Required outcome: public docs, examples, version text, API support,
  deprecations, data migration, and rollback limits agree.
- Verification: documentation checks, migration fixtures, selected examples,
  and compatibility tests.
- Exit criteria: each breaking or stored-data change has proof or an explicit
  irreversible boundary.

### Phase 4 — Run final evidence gates

- Requirements: `DEL-REQ-010` to `DEL-REQ-024`.
- Required outcome: one complete evidence record for the exact candidate.
- Verification: all named commands, runtime matrix, CI, research-skip audit,
  package inspection, and working-tree record.
- Exit criteria: every required gate passes and every exception has approval
  and expiry.

### Phase 5 — Approve release and create later plans

- Requirements: `DEL-REQ-040` to `DEL-REQ-042`.
- Required outcome: approval owner accepts the scope, package, compatibility,
  and evidence records. Any remaining implementation work moves to a separate
  `ce-plan` artifact.
- Verification: approval record and requirement-to-plan trace.
- Exit criteria: the release decision and later plan ownership are explicit.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `DEL-REQ-001` to `DEL-REQ-004` | Pending seam status and this gap register | Approved scope ledger and named owners | `Blocked` |
| `DEL-REQ-005` to `DEL-REQ-009` | Current Jido and sibling manifests | Exact publishable matrix and public-only fixture | `Conflict` |
| `DEL-REQ-010` | Quality alias and past pass record | Fresh pass on exact candidate | `Partial` |
| `DEL-REQ-011` | 90-percent configuration and past 93.6-percent result | Fresh scoped coverage result | `Partial` |
| `DEL-REQ-012` to `DEL-REQ-014` | CI/docs/package setup and past passes | Fresh docs, package, and benchmark results | `Partial` |
| `DEL-REQ-015` | Current focused research result only | Full example result and skip classification | `Partial` |
| `DEL-REQ-016` and `DEL-REQ-017` | Past Elixir 1.18.5/OTP 27 and 1.20.3/OTP 29 results | Fresh results for every claimed runtime | `Partial` |
| `DEL-REQ-018` | Workflow configuration | Successful exact-commit workflow record | `Missing` |
| `DEL-REQ-019` and `DEL-REQ-020` | Historical record lacks current candidate binding; worktree is dirty | Complete evidence fields and clean or recorded diff | `Missing` |
| `DEL-REQ-021` to `DEL-REQ-024` | 11 research skips and `DIST-03` have reasons | Approved scope link for each skip; passing proof for required items | `Partial` |
| `DEL-REQ-025` to `DEL-REQ-028` | Public docs and tests exist; one dependency version drifts; old result files are absent | Candidate-wide consistency and example gate | `Partial` |
| `DEL-REQ-029` to `DEL-REQ-033` | Owner seams recommend additive migration | Approved compatibility register and removal gates | `Missing` |
| `DEL-REQ-034` | Migration guide states separate V2 and V3 storage keys | Executable import fixture if import is claimed | `Partial` |
| `DEL-REQ-035` to `DEL-REQ-037` | Pending owner designs | Scope-specific mixed-version, rollback, and downgrade tests | `Missing` |
| `DEL-REQ-038` | Skipped live-upgrade probes and missing cases | Add complete tests only if the approved scope includes these claims | `Deferred` pending approval |
| `DEL-REQ-039` | README and migration guide state the external-I/O limit | Documentation consistency test | `Proven` for current text |
| `DEL-REQ-040` | This document stays at high-level gates | Review confirms no task-level plan | `Proven` |
| `DEL-REQ-041` and `DEL-REQ-042` | No approved delivery design or later plan | Approved design, then traced `ce-plan` artifact | `Blocked` |

## Migration and compatibility

- No API deprecation or removal is approved in this seam.
- Keep module, Spark, direct-data, Builder, Codec, neutral Agent definitions,
  custom routing, complete checkpoint callbacks, owned children, public PID and
  name APIs, current persistence adapters, static local Topology, and current
  observation paths until their owner seams approve removal gates.
- Add Agent Ref, definition revision, Plugin facets, record changes, and new
  semantic events through compatible stages if their owner requirements enter
  release scope.
- V2 records are not V3 records. Do not point V2 and V3 writers at the same
  storage keys. A supported import must use a V2 reader and a new V3 write.
- Do not claim downgrade. Prove it from a named rollback point or document the
  irreversible boundary.
- Do not claim live Agent, state, Plugin runtime, or Topology upgrade while its
  executable acceptance test is skipped or absent.
- A compatibility interval must use dates or package versions. Phrases such as
  "during migration" are not enough for a release record.

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `DEL-BLK-001` | `Blocker` | User and 99 Delivery | No prerequisite design or release scope is approved. | Approve or change the scope ledger and `DEL-DEC` items. |
| `DEL-BLK-002` | `Blocker` | 90 Package boundaries | No exact publishable V3 package set is proved. | Select the set and pass public-only tests. |
| `DEL-BLK-003` | `Blocker` | Release governance | Release, approval, compatibility, and exception owners are unnamed. | Assign each role. |
| `DEL-BLK-004` | `Blocker` | Owner seams and 99 | Current skips have no approved release-scope classification. | Mark each skipped contract required, deferred, or excluded. |
| `DEL-BLK-005` | `Blocker` | 07 Persistence and 99 | Stored-data upgrade, downgrade, and rollback claims are not selected. | Approve supported paths and proof, or state that they are unsupported. |
| `DEL-BLK-006` | `Assumption` | 00 Overview | Live Agent and live Topology upgrade stay outside the V3 release scope. | Approve or change `DEL-DEC-006`. |
| `DEL-BLK-007` | `Assumption` | 90 Package boundaries | The minimum core set is Jido, `jido_action`, and `jido_signal`. | Decide whether AI or Browser is part of the release claim. |
| `DEL-BLK-008` | `Blocker` | Release owner | Final gates have not run on one exact candidate and package matrix. | Run them only after required implementation and docs close. |
| `DEL-BLK-009` | `Assumption` | Compatibility owner | Supported V3 APIs remain until a version-bounded deprecation passes. | Approve or change `DEL-DEC-005`. |
| `DEL-BLK-010` | `Resolved` | Documentation owners | The design index now uses the three-file seam paths, and Markdown no longer links to the deleted example reports. | Keep repository-wide link checks in the documentation gate. |

## Completion criteria

- [ ] The user has approved or changed every `DEL-DEC` item.
- [ ] The scope ledger classifies every prerequisite requirement and skip.
- [ ] Every release-required requirement has `Proven` evidence.
- [ ] No release-required `Conflict`, `Missing`, or `Blocked` item remains.
- [ ] The exact publishable package matrix passes public-only integration.
- [ ] The compatibility register defines all retained, deprecated, removed,
      migrated, downgrade, and rollback cases.
- [ ] Final quality, coverage, docs, package, benchmark, example, runtime, CI,
      and migration gates are bound to the exact candidate.
- [ ] All gate exceptions have an owner, reason, risk, expiry, and approval.
- [ ] The approval owner accepts the release record.
- [ ] After approval, detailed implementation work is created with `ce-plan`
      outside this seam.
