> Selected and implemented Turn evaluation seam.

# 04 — Turn evaluation

## Briefing

Jido has one command path for direct and live candidate evaluation. The private
Runner now selects the first Router target from the unchanged source Signal,
binds that Signal to the Turn, prepares Plugins, calls `Jido.Exec`, applies
Plugin state updates, and validates a candidate Agent. Bounded, owned Plugin
input is implemented by the seam-05 owner facets.

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
| Route selection | Jido selects the first Router target from the unchanged source Signal before Plugin preparation. | Keep this implemented order and fixed selection. |
| Custom routing | `handle_signal/2` receives the source Signal before preparation. Its validated Turn stays fixed. | Keep the callback and fixed input. |
| Plugin input | Every preparation callback can inspect the complete Agent and change one shared Command. | Use the seam-05 bounded Agent view and one separately owned prepared input for each Plugin. |
| Candidate assembly | Runner protects Plugin-owned state, applies Plugin updates in order, validates Directives, and validates the complete Agent. | Keep one ordered, fail-fast candidate assembly boundary with bounded Plugin contributions. |
| Direct and live use | Both paths share Runner selection, preparation, and finalization. The live path adds admission and Directive batch checks. | Keep candidate parity and live-only policy separation. |
| Errors and stages | Private runtime errors identify a closed evaluator stage and map to current Outcome stages. | Keep public direct errors unchanged. Let seams 08 and 13 own runtime and Outcome policy. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Route order migration | Plugins that selected behavior by changing Signal type now run after fixed selection. | Document and test source-Signal, first-match selection. | 04 Turn evaluation, with 05 Plugins |
| Plugin preparation is not isolated | A Plugin can read the complete Agent and replace another Plugin's prepared data. | Bounded views and separately owned inputs. | 05 Plugins, consumed by 04 |
| Shared evaluator boundary is split | Live work uses admission, async Exec, Server finalization, and live-only checks. | One candidate contract with a clear private prepare/resume shape or one complete call. | 04 Turn evaluation and 08 Agent Server |
| Runtime stage evidence | The evaluator stage set maps to current Outcome stages. | Complete runtime and observation evidence. | 08 and 13 |
| Plugin isolation proof is incomplete | First-match routing now passes, but the isolation research case is still seam-05 work. | Passing bounded-view and owned-input evidence. | 05 Plugins |
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
  [02 Agent authoring](../02_agent-authoring/alignment.md). Overview, package
  boundaries, Agent, Agent authoring, and the seam-12 error contract are
  approved. [03 Agent identity](../03_agent-identity/alignment.md) was also
  reviewed; it does not own candidate evaluation.
- Dependents: 05 Plugins, 06 Commit and effects, 08 Agent Server, 13
  Observability, and 99 Delivery.
- Owner dependencies: seam-05 bounded callback values and seam-08 and seam-13
  runtime evidence. V3 does not pin loaded executable code to Agent `vsn`.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
