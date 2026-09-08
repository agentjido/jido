> Seam review entry point. This document is pending approval.

# 04 — Turn evaluation

## Briefing

Jido has one working command path for direct and live execution. The private
Runner prepares Plugins, selects a Turn, calls `Jido.Exec`, applies Plugin state
updates, and validates a candidate Agent. The main target change is to select
one fixed executable from the unchanged source Signal before Plugin
preparation. The target also gives each Plugin bounded, owned input and makes
the shared candidate-evaluation boundary clear. All target requirements and
decisions are pending approval.

## Why this seam exists

- Owner: the private Jido Turn evaluation boundary.
- Owns: source-Signal preservation, fixed Turn selection, evaluator stage
  order, executable-result normalization, candidate assembly, and direct/live
  candidate parity.
- Does not own: route declaration and Router precedence, Plugin callback types,
  Action or Flow execution semantics, persistence, commit, Directive handling,
  cancellation, runtime task structure, or Turn Outcome publication.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Route selection | Plugin preparation runs first and can change the Signal used for routing. Jido rejects zero or multiple Router targets. | Keep the received Signal as the source. Use the first Router target from that source before preparation and keep it fixed. |
| Custom routing | `handle_signal/2` can return a validated `Jido.Agent.Turn`. | Keep the callback. Call it with the source Signal before Plugin preparation and keep its returned executable and input fixed. |
| Plugin input | Every preparation callback can inspect the complete Agent and change one shared Command. | Use the seam-05 bounded Agent view and one separately owned prepared input for each Plugin. |
| Candidate assembly | Runner protects Plugin-owned state, applies Plugin updates in order, validates Directives, and validates the complete Agent. | Keep one ordered, fail-fast candidate assembly boundary with bounded Plugin contributions. |
| Direct and live use | Both paths share Runner preparation and finalization, but the live path adds admission and Directive batch checks. | Share candidate semantics. Keep live-only admission, limits, task control, commit, and dispatch outside the parity claim. |
| Errors and stages | Errors use mixed raw and typed values. Outcome stages also describe runtime work. | Use defined seam-12 errors and a closed private evaluator-stage set. Let seams 08 and 13 own runtime and Outcome stages. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Route order conflicts with the target | A Plugin can replace the selected behavior. | Source-Signal, first-match selection that stays fixed. | 04 Turn evaluation, with 01 Agent and 05 Plugins |
| Plugin preparation is not isolated | A Plugin can read the complete Agent and replace another Plugin's prepared data. | Bounded views and separately owned inputs. | 05 Plugins, consumed by 04 |
| Shared evaluator boundary is split | Live work uses admission, async Exec, Server finalization, and live-only checks. | One candidate contract with a clear private prepare/resume shape or one complete call. | 04 Turn evaluation and 08 Agent Server |
| Error and stage contracts differ | Direct, live, and observation paths can describe the same fault in different ways. | Defined evaluator errors and an explicit mapping to runtime observation. | 04, 08, 12, and 13 |
| Target proof is incomplete | Research cases for first-match routing and Plugin isolation are skipped. | Passing direct/live route, parity, isolation, failure, and stale-result evidence. | 04, 05, and 08 |
| Executable code is not pinned | A definition revision does not freeze loaded Action or Flow code for a Turn. | An explicit V3 non-guarantee or an owned code-revision contract. | `jido_action` and 04 Turn evaluation |

## Decisions requested

1. **Selection order:** Approve first-match selection from the unchanged source
   Signal before Plugin preparation. Effect: a Plugin cannot change the Turn's
   executable.
2. **Custom routing:** Keep `handle_signal/2`. Treat its valid Turn as fixed
   selection and fixed input. Effect: current custom routing remains supported.
3. **Parity boundary:** Define parity at candidate evaluation, not at live
   admission, limits, commit, or Directive handling. Effect: direct and live
   candidate production has one testable contract without moving Server policy.
4. **Private stages:** Use `route`, `prepare`, `input`, `execute`, `compose`, and
   `validate` as the private evaluator stages. Effect: errors can be mapped to
   Server and Outcome stages without sharing one vocabulary.
5. **Live task shape:** Let seam 08 choose one complete task or a private
   prepare/resume protocol. Effect: this seam does not set OTP structure.
6. **Code revision:** State that V3 does not pin loaded Action or Flow code for
   a Turn. Effect: definition revision remains a restore check, not a code
   snapshot guarantee.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md), and
  [02 Agent authoring](../02_agent-authoring/alignment.md). All are pending
  draft prerequisites. [03 Agent identity](../03_agent-identity/alignment.md)
  was also reviewed; it does not own candidate evaluation.
- Dependents: 05 Plugins, 06 Commit and effects, 08 Agent Server, 13
  Observability, and 99 Delivery.
- Blockers: prerequisite approval; seam-05 bounded callback values; the final
  private/live stage mapping; and the code-revision decision.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
