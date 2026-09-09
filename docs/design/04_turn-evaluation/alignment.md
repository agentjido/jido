> Seam alignment plan. This document is pending approval.

# Turn evaluation alignment

## Status

- Design reviewed: 2026-09-08.
- Code and implementation reviewed: 2026-09-09 on branch `v3-spike`, after
  Agent identity commit `8265fb93`.
- Prerequisite alignments:
  [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md), and
  [02 Agent authoring](../02_agent-authoring/alignment.md). The
  [03 Agent identity](../03_agent-identity/alignment.md) alignment was reviewed
  as related context.
- Alignment state: `Seam-owned route and evaluator work implemented; Plugin
  isolation remains with seam 05`.

The alignment state is execution status. It is not document approval.
Overview, package boundaries, Agent, Agent authoring, and the seam-12 error
contract are approved. This seam remains pending approval. The changed seam-12
package inventory documents also remain pending approval.

## Inputs and evidence

### Design

- `docs/design/VISION.md`: sets one shared Turn model, direct testability, and
  the boundary between candidate evaluation and live commit.
- `docs/design/00_overview/design.md`: recommends source-Signal first-match
  routing, fixed selection, isolated Plugin input, and shared candidate
  evaluation.
- `docs/design/90_package-boundaries/design.md`: keeps Agent candidate assembly
  in Jido and executable and Signal semantics in their lower packages.
- `docs/design/12_errors-and-contracts/design.md`: defines callback fault
  normalization, invariant exits, stable errors, and portable-value rules.
- `docs/design/01_agent/design.md`: keeps direct `cmd/3`, custom
  `handle_signal/2`, combined state, and one candidate validation boundary.
- `docs/design/02_agent-authoring/design.md`: preserves route declaration order,
  route defaults, custom predicates, and normalized executable targets.
- `docs/design/03_agent-identity/design.md`: separates logical identity from
  Turn selection and runtime handles. It adds no candidate-evaluation duty.
- `docs/design/04_turn-evaluation/design.md`: states this seam's pending target
  contract and requirements.

### Canonical code

| Evidence | Current behavior |
| --- | --- |
| `lib/jido/agent.ex:439-477` | `Agent.transition/2` validates complete state. `cmd/3` calls the private Runner. The default `handle_signal/2` calls the Runner route helper. |
| `lib/jido/agent/command.ex:1-74` | A Plugin Command contains the complete Agent, Signal, and caller context. |
| `lib/jido/agent/turn.ex` | A public prepared Turn contains the executable, input, and unchanged source Signal. Existing constructors remain compatible. |
| `lib/jido/agent/command/runner.ex` | Direct execution selects before preparation, calls `Jido.Exec.run/4`, and finalizes. Private Server results use a closed stage set. |
| `lib/jido/agent/command/runner.ex` | Runner keeps source and effective Signals separate and gives route input effective data without changing the selected executable. |
| `lib/jido/agent/dsl/compiler.ex`; `lib/jido/agent.ex` | Generated Agents expose a private default-handler marker so the evaluator can keep default route data behavior and custom Turn input behavior distinct. |
| `lib/jido/agent/command/runner.ex:120-154,229-260` | Finalization normalizes executable output, protects Plugin state, validates Directive ownership, applies Plugin state updates, and validates the candidate. |
| `lib/jido/plugin.ex:2-24,67-102` | Public Plugin documentation and callbacks expose live admission, a shared Command preparation callback, state update, and Directive ownership. |
| `lib/jido/plugin.ex:696-723` | Plugin preparation is a serial, fail-fast reduce in declaration order. |
| `lib/jido/plugin.ex:826-875` | Plugin state updates are serial. Each callback receives its current owned state and owned Directives, but there is no separate prepared input or bounded Transition value. |
| `lib/jido/agent_server.ex:1285-1431` | A live Turn gets a stable ID. Optional admission runs before Runner preparation. The Server then starts asynchronous execution. |
| `lib/jido/agent_server.ex:1440-1490` | `Jido.Exec` or a configured adapter performs live execution. Runner finalization runs later in the Server. Live-only Directive batch checks follow it. |
| `lib/jido/agent_server.ex:1493-1564` | The Server persists before it changes live state, increments the revision once, replies, and starts Directives. Pre-commit failure keeps current state. |
| `lib/jido/agent_server/active_turn.ex:48-129` | ActiveTurn keeps source and effective Signals, start and committed revisions, and Directive progress. |
| `lib/jido/agent/turn/outcome.ex:13-190` | The public Outcome uses five runtime stages and stores complete source and effective Signals. |
| `lib/jido/agent_server/options.ex` | Seam 08 adds one `turn_timeout` for active pre-commit work. `directive_timeout` remains a separate limit for Directive work and lower execution-adapter operations. |

### Tests and examples

| Evidence | Current proof |
| --- | --- |
| `test/jido/agent_test.exs:292-316,581-646` | One route works, route data overrides defaults, wildcards and predicates work, and multiple matches are an error. |
| `test/jido/agent_test.exs:718-858` | Custom routing, context rules, direct errors, Directives, equal-input behavior, and Flow execution work. |
| `test/jido/plugin/contract_test.exs:490-563` | Plugin preparation order, rejection, invalid results, Agent replacement protection, and state validation are covered. |
| `test/jido/plugin/ordering_test.exs:198-232` | Live admission follows declaration order and stops at the first error. |
| `test/jido/agent_server/context_test.exs:227-272` | Live context, effective Signal, Plugin state composition, and revision behavior are covered. |
| `test/jido/agent_server/directive_execution_test.exs:27-117` | Commit occurs before Directive work. Invalid live Directive batches do not commit. Source and effective Signals can differ. |
| `test/jido/agent_server/public_api_test.exs:308-330,368-484` | A blocked Turn preserves sender order. Cancellation uses the stable Turn ID and does not commit the cancelled Turn. |
| `test/jido/agent_server/runtime_boundary_test.exs:232-259` | Normal `Jido.Exec` execution can exceed `directive_timeout`. |
| `test/jido/persistence_test.exs:259-345` | A successful Turn writes revision 1. A conflict prevents live state change and Directive dispatch. |
| `test/jido/agent/turn/outcome_test.exs:24-103` | Current Outcome stage, status, revision, Directive count, and time rules are covered. |
| `test/examples/99_research/99_09_route_selection/route_selection_test.exs` | Direct/live parity, fallback, exact-first precedence, and fixed source-Signal selection all pass. |
| `test/jido/agent/turn_evaluation_test.exs` | Custom routing runs before preparation, Turn source identity is exact, direct/live candidates match, and private stage tags are bounded. |
| `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:6-34` | Plugin state write protection, bounded reads, and separate prepared inputs all pass. |

## Retained baseline

- One immutable Agent and one Signal produce either an error or one candidate
  Agent and ordered Directive list.
- Direct `Jido.Agent.cmd/3` uses no Server and performs no commit or Directive
  handling.
- `Jido.Agent.Turn` remains the supported custom routing return value.
- One Turn executes one Action or Flow through one outer `Jido.Exec` call.
- Effective Signal data overrides route defaults in the default route path.
- Plugin preparation and state updates run serially in declaration order and
  stop at the first error.
- Executables cannot change Plugin-owned state. Plugins can replace only their
  owned state entry. Jido validates the complete candidate Agent.
- Jido validates Directive ownership before a candidate crosses the live
  commit boundary.
- Executable I/O can occur before commit and has no rollback guarantee.
- Live admission, task control, revision checks, persistence, commit,
  cancellation, Directive limits, dispatch, and Outcomes remain Server-owned.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `TURN-GAP-001` | `TURN-REQ-001`, `TURN-REQ-005`, `TURN-REQ-008`, `TURN-REQ-019`, `TURN-REQ-020`, `TURN-REQ-044` | Runner, Turn, focused evaluation tests, and route research case | Selection uses the unchanged source Signal before preparation and stays fixed. | `Aligned` |
| `TURN-GAP-002` | `TURN-REQ-006`, `TURN-REQ-007` | Runner, Agent route tests, and route research case | Jido selects the first Router target and preserves the normalized no-route error. | `Aligned` |
| `TURN-GAP-003` | `TURN-REQ-011` to `TURN-REQ-013` | Runner and custom-selection tests | The callback receives the source Signal before Plugins. Its executable and input stay fixed. | `Aligned` |
| `TURN-GAP-004` | `TURN-REQ-009`, `TURN-REQ-010` | Runner materialization and route-default tests | Route defaults stay fixed and effective Signal data has precedence. | `Aligned` |
| `TURN-GAP-005` | `TURN-REQ-014` to `TURN-REQ-018` | Plugin Command and preparation code; isolation research case | Order and fail-fast behavior work. Complete Agent access and shared prepared data do not meet isolation. | `Retain` order; `Change` callback data after seam 05. |
| `TURN-GAP-006` | `TURN-REQ-021` to `TURN-REQ-026` | Runner execution and finalization; Agent and Plugin tests | Outer execution, output shape, state protection, and ownership checks mostly work. Error codes remain incomplete. | `Retain`; align errors with seam 12. |
| `TURN-GAP-007` | `TURN-REQ-027` to `TURN-REQ-031` | Plugin state update code; isolation research case | Serial owned-state update works, but bounded Transition, owned prepared input, and contribution isolation do not exist. | `Change` after seam-05 contract approval. |
| `TURN-GAP-008` | `TURN-REQ-032`, `TURN-REQ-033` | Runner lines 120-133; ActiveTurn lines 60-70 | Candidate validation works. No single private result carries all recommended metadata. | `Retain` validation; `Change` private handoff. |
| `TURN-GAP-009` | `TURN-REQ-034` to `TURN-REQ-036` | Callback wrappers, staged Runner results, and Agent Server mapping | Callback faults use seam-12 errors. Private Server results use the closed stage set. | `Aligned` for current callbacks and runtime mapping |
| `TURN-GAP-010` | `TURN-REQ-037` to `TURN-REQ-040` | Agent `cmd/3`, Runner, and Agent Server | Direct and live share preparation and finalization, but live execution splits the boundary. | `Retain` candidate semantics; allow one call or prepare/resume. |
| `TURN-GAP-011` | `TURN-REQ-041`, `TURN-REQ-042` | Agent Server lines 1370-1545 | Runtime policy is outside Runner, but the parity boundary is not stated and live-only checks occur after shared finalization. | `Clarify` ownership and parity. |
| `TURN-GAP-012` | `TURN-REQ-004`, `TURN-REQ-043` | Direct Agent tests; current architecture | The no-Plugin path works. No contract test proves the external-I/O non-rollback statement. | `Retain`; add bounded documentation and evidence. |
| `TURN-GAP-013` | All requirements | Focused tests above | There is no requirement-mapped direct/live acceptance set for route, Plugin, Action, Flow, error, and policy boundaries. | `Change evidence`. |

## Dispositions of superseded design claims

This table retains or resolves every distinct claim from the replaced seam
proposal and gap report. Git history keeps the removed text.

| Superseded claim | Disposition | Reason and owner |
| --- | --- | --- |
| The evaluator must be a fixed compiled-Elixir pipeline and must not use a Runic graph. | `Retain semantic limit`; remove the exact function-shape rule. | One fixed outer order is required. A selected Flow can use Runic through `Jido.Exec`. |
| `Agent.cmd/3` and live execution must run one complete evaluator function. | `Replace`. | They must share candidate semantics. Seam 08 can use one call or a private prepare/resume protocol. |
| Live evaluation must run in one owner-bound task. | `Defer`. | Task count and ownership are Agent Server concerns. This seam requires stale results to have no evaluation authority. |
| Equal inputs always make evaluation deterministic. | `Clarify`. | Ordering is deterministic, but executable external responses can differ. Parity proof must control the executable result. |
| The executable output must remain private from Plugins and public command results. | `Retain`. | Bounded Plugin input and private evaluator metadata preserve this rule. |
| The exact public types must be `Plugin.Context`, `Plugin.Transition`, and `Plugin.Contribution`. | `Defer exact types`. | Seam 05 owns callback values, fields, and migration. This seam owns required isolation. |
| Plugin preparation and composition must be serial, fail-fast reduces with no Agent-level concurrency. | `Retain target behavior`; remove the required reducer implementation. | Order and stopping behavior are observable. Function choice is private. |
| Contribution assembly must avoid an intermediate list. | `Remove as contract`. | This is an implementation choice with no required public effect. |
| A private module must be named `Jido.Agent.Turn.Evaluator` with one exact `run/3` tuple. | `Replace`. | Keep a private evaluator contract and closed stages. Select names and private tuple shapes in the later implementation plan. |
| Every callback fault becomes a Splode error and every internal invariant crashes the live runtime. | `Retain`, pending seam 12. | `TURN-REQ-034` and `TURN-REQ-035` use the prerequisite error policy. |
| The Turn seam owns stable Turn IDs, task references, cancellation, late-result rejection, and a complete `turn_timeout`. | `Implemented by seam 08`. | This seam supplies stage and private-result inputs. Seam 08 owns live control and the active pre-commit limit. |
| Direct `cmd/3` has no Server cancellation or Server Turn timeout. | `Retain`. | Direct evaluation runs at the caller boundary and uses executable options only. |
| The Turn seam owns persistence, revision increment, commit reply order, Directive dispatch, and terminal settlement. | `Remove from this seam`. | Seams 06, 08, and 13 own those rules. Evaluation ends with a validated candidate. |
| A state version must be an evaluator input. | `Remove`. | Revision stability is a live owner invariant. Equal evaluator input is defined without commit revision. |
| The evaluator must build a public Result value. | `Remove`. | Direct success stays a tagged evaluation return. Live result and Turn Outcome are separate owner-seam values. |
| The current five Outcome stages must become evaluator stages. | `Remove`. | Private evaluator stages and public runtime observation need an explicit mapping, not one shared set. |
| Outcomes must contain complete Signals, or must contain IDs only. | `Defer`. | Seams 08 and 13 own Outcome data and privacy. This seam only preserves source and effective values for private use. |
| Live Plugin admission must be part of the pure evaluator, or must be removed. | `Replace`. | Keep admission as live-only preprocessing. It cannot replace the source Signal or fixed executable. Seam 05 owns the callback. |
| Direct and live paths must enforce every Directive batch rule at the same point. | `Clarify`. | Candidate ownership validation is shared. Server limits and dispatch-target policy are live-only. |
| Route parameters must be a new stored public value. | `Remove public type`; retain private meaning. | Fixed default-route data must survive preparation, but it needs no public struct. |
| A Plugin contribution can add owned Directives. | `Defer`. | Seam 05 must decide contribution authority. This seam can validate any returned Directive by owner. |
| A definition revision pins Action or Flow code for a Turn. | `Remove for V3`, pending decision. | `Jido.Exec` uses the selected executable and currently loaded code. `jido_action` owns any future code-revision contract. |
| The first release must support local evaluation only, one active live Turn, serial Plugin work, and no mid-Turn persistence or recovery. | `Retain seam-owned limits`; defer live concurrency details. | No mid-evaluation persistence, recovery, distributed evaluation, or Plugin-defined stages enter this target. |

## High-level work sequence

This sequence defines outcomes and gates. It is not the formal implementation
plan. Create that plan only after the design is approved.

### Phase 0 — Resolve prerequisites and Turn decisions

- Requirements: all `TURN-REQ` items.
- Required outcome: approve or replace the route, custom callback, parity,
  stage, task-shape, admission, and code-revision decisions.
- Constraints: do not treat pending prerequisite requirements as approved.
- Compatibility: keep direct `cmd/3`, custom routing, Plugin declaration order,
  and current live APIs.
- Verification: cross-seam owner review with 01, 05, 08, 12, and
  `jido_action`.
- Exit criteria: no unresolved owner conflict remains in `design.md`.

### Phase 1 — Lock fixed source-Signal selection

- Requirements: `TURN-REQ-001` to `TURN-REQ-013`.
- Required outcome: one source Signal selects the first Router target or one
  custom Turn before preparation, and selection stays fixed.
- Constraints: keep Router ordering in `jido_signal` and custom routing in
  `Jido.Agent`.
- Compatibility: document the change from ambiguous-route errors and
  route-changing Plugins.
- Verification: direct and live exact, `*`, `**`, predicate, priority,
  declaration-order, no-route, defaults, and custom-callback cases.
- Exit criteria: all selection cases pass with the same fixed Turn.

### Phase 2 — Establish bounded Plugin evaluation input

- Requirements: `TURN-REQ-014` to `TURN-REQ-020`, `TURN-REQ-027` to
  `TURN-REQ-031`.
- Required outcome: serial Plugin preparation and composition use seam-05
  bounded views and separate owned inputs.
- Constraints: preserve declaration order, fail-fast behavior, state write
  ownership, and no-Plugin operation.
- Compatibility: provide the seam-05 migration path for current Command and
  `update_state/3` callbacks.
- Verification: isolation, ordering, first-error, owned-state, and owned-
  Directive tests.
- Exit criteria: no Plugin can read or replace another owner's evaluation data.

### Phase 3 — Unify candidate evaluation and errors

- Requirements: `TURN-REQ-021` to `TURN-REQ-043`.
- Required outcome: direct and live paths use one candidate contract with
  defined errors, private stages, and live-policy exclusions.
- Constraints: one outer `Jido.Exec` call; no evaluator commit, timer, task, or
  dispatch ownership.
- Compatibility: keep public `cmd/3` and `Jido.Agent.Turn` results.
- Verification: Action, Flow, invalid output, callback fault, Directive,
  candidate, parity, and external-I/O failure tests.
- Exit criteria: every requirement has passing direct or live evidence and an
  explicit stage mapping for seams 08 and 13.

### Phase 4 — Close cross-seam acceptance

- Requirements: all `TURN-REQ` items.
- Required outcome: downstream seams use the approved candidate contract.
- Constraints: runtime and observation documents must not assign commit or
  cancellation authority to the evaluator.
- Compatibility: complete migration proof before removing any old Plugin
  callback path or ambiguous-route error expectation.
- Verification: run focused Agent, Plugin, Agent Server, persistence, Outcome,
  and research example tests against the release-compatible package set.
- Exit criteria: the acceptance matrix has no `Missing`, `Partial`, or
  `Conflict` entry.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `TURN-REQ-001` to `TURN-REQ-003` | Runner and Turn evaluation tests | Ordered direct/live stage test with a route-changing Plugin. | `Proven` |
| `TURN-REQ-004` | Direct Agent tests run without Plugins. | Keep one Action and one Flow no-Plugin case in the mapped suite. | `Proven` |
| `TURN-REQ-005` to `TURN-REQ-010` | Agent route tests and the passing route-selection example | First-match matrix and fixed-default tests with prepared Signal changes. | `Proven` |
| `TURN-REQ-011` to `TURN-REQ-013` | Custom callback and Turn evaluation tests | Source-before-prepare and callback-fault matrix. | `Proven` |
| `TURN-REQ-014`, `TURN-REQ-015` | Plugin preparation and live admission order tests. | Keep both direct preparation and live admission coverage. | `Proven` |
| `TURN-REQ-016` to `TURN-REQ-018` | Isolation research assertions are skipped. | Seam-05 bounded-view and owned-input tests. | `Missing` |
| `TURN-REQ-019`, `TURN-REQ-020` | Direct and live route-selection and custom-selection tests | Changed effective type and data cannot change selection. | `Proven` |
| `TURN-REQ-021`, `TURN-REQ-022` | Runner and Agent Server use one outer `Jido.Exec` operation. | Action and Flow call-count tests for direct and live paths. | `Proven` |
| `TURN-REQ-023` to `TURN-REQ-026` | Runner finalization and Plugin contract tests cover state and Directive ownership. | Add stable seam-12 error-code assertions. | `Partial` |
| `TURN-REQ-027` | Plugin state update reduce is ordered and fail-fast. | Keep declaration-order evidence with three Plugins. | `Proven` |
| `TURN-REQ-028` to `TURN-REQ-030` | Owned state and owned Directives are bounded, but Agent view and prepared input are not. | Contribution projection and cross-Plugin denial tests. | `Partial` |
| `TURN-REQ-031`, `TURN-REQ-032` | Plugin failure discards the result; Agent transition validates complete state. | One candidate-discard assertion for each contribution failure type. | `Proven` |
| `TURN-REQ-033` | Candidate and Directives return; live ActiveTurn stores effective Signal. No one private handoff has all fields. | Private result or prepare/resume contract tests. | `Partial` |
| `TURN-REQ-034` | Agent and Plugin wrapper fault tests | Table test for return, raise, throw, exit, and defined error at each callback. | `Proven` for current callbacks |
| `TURN-REQ-035` | Runner no longer catches internal finalization faults; ActiveTurn checks source identity | Inject a broken evaluator invariant and prove OTP exit and restore behavior. | `Partial`; restart proof belongs to seam 08 |
| `TURN-REQ-036` | Staged Runner results, focused stage tests, and Agent Server mapping | Keep every private stage and explicit live mapping covered. | `Proven` for current stages |
| `TURN-REQ-037` to `TURN-REQ-039` | `Agent.cmd/3` uses Runner and returns a candidate without commit or dispatch. | Keep public return and no-side-effect tests. | `Proven` |
| `TURN-REQ-040` | Direct and live share preparation and finalization. One-route parity passes. | Full Action, Flow, Plugin, failure, output, and Directive parity matrix. | `Partial` |
| `TURN-REQ-041` | Server-only Directive limits and dispatch checks exist after Runner finalization. | Tests that separate shared ownership checks from live policy checks. | `Partial` |
| `TURN-REQ-042` | Runner owns no process, timer, persistence, commit, dispatch, or cancellation state. | Architecture check after the private boundary changes. | `Proven` |
| `TURN-REQ-043` | Current code makes no rollback claim. | Executable-effect test that fails before commit and documents retained external work. | `Partial` |
| `TURN-REQ-044` | Turn constructors, Runner source binding, ActiveTurn identity check, and focused tests | Keep exact source Signal evidence in direct and live evaluation. | `Proven` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Multiple routes | First-match selection changes a current RoutingError. Document precedence and add direct/live proof before release. |
| Route-changing Plugins | Keep the source and effective Signals visible to bounded internal code. Provide a migration note for Plugins that changed Signal type to select behavior. |
| Custom routing | Keep `handle_signal/2` and `Jido.Agent.Turn`. Move callback invocation before preparation only with source, input, and context tests. |
| Route defaults | Keep effective Signal data precedence and the authoring seam's legacy defaults compatibility rule. |
| Plugin callbacks | Seam 05 must provide a staged path from complete Command access and `update_state/3` to bounded views and owned input. |
| Direct execution | Keep `Jido.Agent.cmd/3` return shape and process-free use. Do not expose private execution metadata. |
| Live execution | Keep current Agent Server calls. A private prepare/resume change must preserve late-result, cancellation, state, and reply behavior. |
| Errors | Move raw terms to approved seam-12 errors without changing already-composed adjacent-package errors. |
| Outcomes | Do not change Outcome fields or stages in this seam. Seams 08 and 13 own any migration and compatibility form. |
| Code revision | Do not claim loaded-code pinning. A later guarantee needs a `jido_action` owner and release-compatible proof. |
| Turn source | `source_signal` is additive. Existing two-argument Turn constructors remain supported for callback construction. |

Rollback must restore the old route and Plugin callback behavior together. A
mixed release must not select by the source Signal and then call a Plugin that
depends on changing route choice without a clear compatibility adapter.

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `TURN-BLK-001` | `Resolved` | 00 Overview | Source-Signal first-match selection and shared candidate evaluation are approved. | Preserve the Overview contract. |
| `TURN-BLK-002` | `Resolved` | 90 Package boundaries | Jido owns candidate assembly. Lower packages own execution and routing semantics. | Preserve the package boundary. |
| `TURN-BLK-003` | `Resolved contract` | 12 Errors and contracts | Callback normalization, invariant exits, and stable codes are approved. | The package inventory document revalidation does not change this contract. |
| `TURN-BLK-004` | `Resolved` | 01 Agent | Direct `cmd/3`, custom routing, combined state, and transition requirements are approved. | Preserve the Agent contract. |
| `TURN-BLK-005` | `Approved authoring input` | 02 Agent authoring and `jido_signal` | Authoring preserves Router order and current route-default precedence. | Confirm against the release-compatible `jido_signal` package. |
| `TURN-BLK-006` | `Resolved implementation input` | 05 Plugins | Bounded Agent views, owned prepared inputs, Transition data, and contribution authority use the four-owner Plugin contract. | Preserve seam-05 owner boundaries. |
| `TURN-BLK-007` | `Blocker` | 08 Agent Server and 13 Observability | Private evaluator stages have no approved mapping to live control and Outcome stages. | Approve one explicit mapping without making the vocabularies identical. |
| `TURN-BLK-008` | `Assumption` | 08 Agent Server | Live admission remains outside candidate evaluation and cannot change source-Signal selection. | Approve or change `TURN-DEC-007`. |
| `TURN-BLK-009` | `Resolved design` | 04 Turn evaluation and `jido_action` | Agent `vsn` does not pin loaded executable code. | V3 uses the code loaded when `Jido.Exec` invokes the selected executable. |
| `TURN-BLK-010` | `Assumption` | 06 Commit and effects and 08 Agent Server | State revision is not evaluator input. The Server checks and advances it at commit. | Confirm in the owner seams. |
| `TURN-BLK-011` | `Assumption` | 03 Agent identity | Stable Agent Ref does not change candidate evaluation semantics. | Keep Ref and runtime handles out of evaluator authority. |

## Completion criteria

- [ ] All approved `TURN-REQ` requirements have `Proven` evidence.
- [ ] No unresolved `Conflict` remains.
- [x] The source-Signal route research case passes.
- [ ] The Plugin-isolation research case passes after seam-05 bounded inputs.
- [ ] Direct and live candidate parity has Action, Flow, Plugin, failure,
      output, and Directive coverage.
- [ ] Seam 08 and seam 13 use an explicit evaluator-stage mapping.
- [ ] Compatibility work for routing, custom callbacks, Plugins, and errors is
      complete.
- [ ] Dependent seam documents use the approved contract.
