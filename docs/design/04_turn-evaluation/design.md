> Target seam design. This document is pending approval.

# Turn evaluation design

## Scope and owner

- Owner: the private Jido Turn evaluation boundary.
- In scope: source and effective Signal roles, fixed Turn selection, evaluation
  order, Plugin preparation use, `Jido.Exec` use, candidate assembly, private
  evaluation results, and direct/live candidate parity.
- Out of scope: route declaration and Router precedence in `jido_signal`;
  Plugin callback value shapes in seam 05; Action and Flow result semantics in
  `jido_action`; Agent fields and transition rules in seam 01; error classes in
  seam 12; and live admission, tasks, timeouts, cancellation, persistence,
  commit, Directive handling, and Outcomes in seams 06, 08, and 13.

## Model

One evaluation starts with an immutable Agent instance and one source Signal.
The source Signal is the value received for the Turn and does not change. Live
admission can add bounded evaluation context, but the Agent Server must keep the
source Signal separate.

The recommended sequence is:

```text
Agent A0 + source Signal S0
  -> select one fixed Turn from S0
  -> prepare Plugins in declaration order
  -> build executable input from the effective Signal
  -> call Jido.Exec once
  -> normalize the executable result
  -> apply bounded Plugin contributions in declaration order
  -> validate one candidate Agent A1 and Directive list D
  -> return a private evaluation result
```

The default route path uses the first target returned by the Signal Router.
`jido_signal` owns target ordering. Jido does not sort the returned targets a
second time. A custom `handle_signal/2` callback remains supported. Jido calls
it with the source Signal before Plugin preparation. Its valid
`Jido.Agent.Turn` fixes both the executable and its input.

For a default route, selection keeps the target and route defaults private.
After Plugin preparation, Jido merges the route defaults with effective Signal
data. Effective Signal data has precedence. Preparation can change bounded
input data and context, but it cannot change the selected executable or start
another route lookup.

An Action or Flow can do synchronous external work through `Jido.Exec`. The
evaluator does not promise rollback of that work. The executable is the only
writer of domain state. Each stateful Plugin can replace only its own complete
top-level Plugin state entry. Jido assembles and validates the complete
candidate.

The private evaluator can use one function or a prepare/resume protocol. That
choice does not change the semantic order. The evaluator owns no process or
runtime state. Seam 08 owns the live task shape and all stale-result checks.

## Requirements

All requirements are recommended target behavior. They are pending approval.

### Evaluation input and order

`TURN-REQ-001`: When Turn evaluation starts, the Turn evaluator shall preserve
the received Signal as the unchanged source Signal.

`TURN-REQ-002`: When Turn evaluation starts, the Turn evaluator shall validate
the Agent instance, source Signal, and evaluation options before executable
work starts.

`TURN-REQ-003`: When Turn evaluation runs, the Turn evaluator shall process
selection, Plugin preparation, input construction, execution, Plugin
composition, and candidate validation in that order.

`TURN-REQ-004`: Where an Agent declares no Plugins, the Turn evaluator shall
run the same selection, execution, and candidate-validation path without a
Plugin dependency.

### Fixed Turn selection and input

`TURN-REQ-005`: When the default routing path selects a Turn, the Turn evaluator
shall call the Signal Router with the source Signal.

`TURN-REQ-006`: When the Signal Router returns one or more targets, the Turn
evaluator shall select the first returned target.

`TURN-REQ-007`: If the Signal Router returns no target, then the Turn evaluator
shall return the defined no-route error before Plugin preparation.

`TURN-REQ-008`: When the Turn evaluator selects an executable, the Turn
evaluator shall keep that executable unchanged for the complete evaluation.

`TURN-REQ-009`: When the default routing path selects route defaults, the Turn
evaluator shall keep those defaults unchanged for the complete evaluation.

`TURN-REQ-010`: When the default routing path builds executable input, the Turn
evaluator shall merge the fixed route defaults with effective Signal data so
that effective Signal data has precedence.

`TURN-REQ-011`: Where an Agent module defines `handle_signal/2`, the Agent
boundary shall call it with the source Signal before Plugin preparation.

`TURN-REQ-012`: When `handle_signal/2` returns a valid `Jido.Agent.Turn`, the
Turn evaluator shall keep its executable and input unchanged for the complete
evaluation.

`TURN-REQ-013`: If `handle_signal/2` returns an invalid value or callback fault,
then the Agent boundary shall return the defined seam-12 callback error before
executable work starts.

### Plugin preparation and isolation

`TURN-REQ-014`: When an Agent declares more than one Plugin, the Plugin
boundary shall run Turn preparation serially in declaration order.

`TURN-REQ-015`: If Plugin preparation fails, then the Plugin boundary shall
stop preparation at the first failure.

`TURN-REQ-016`: When a Plugin prepares a Turn, the Plugin boundary shall give
it only the Agent view declared by that Plugin's seam-05 contract.

`TURN-REQ-017`: When a Plugin prepares a Turn, the Plugin boundary shall store
that Plugin's prepared input separately from every other Plugin's prepared
input.

`TURN-REQ-018`: If a Plugin tries to replace another Plugin's prepared input,
then the Plugin boundary shall reject the change before executable work starts.

`TURN-REQ-019`: When Plugin preparation changes the Signal, the Turn evaluator
shall keep the changed value as the effective Signal without changing the
source Signal.

`TURN-REQ-020`: When Plugin preparation changes the effective Signal, the Turn
evaluator shall not replace the selected executable or run route lookup again.

### Execution and candidate assembly

`TURN-REQ-021`: When Turn execution starts, the Turn evaluator shall call
`Jido.Exec` one time for the selected Action or Flow.

`TURN-REQ-022`: When the Turn evaluator calls `Jido.Exec`, it shall pass the
exact executable selected for that Turn.

`TURN-REQ-023`: While a Turn is in evaluation, the Agent boundary shall allow
only the selected Action or Flow to propose domain state.

`TURN-REQ-024`: If executable success output is not a complete plain state map,
then the Turn evaluator shall return the defined invalid-output error.

`TURN-REQ-025`: If executable output changes a Plugin-owned state entry, then
the Turn evaluator shall reject the output before candidate validation.

`TURN-REQ-026`: When executable output includes Directives, the Turn evaluator
shall validate every Directive against its built-in or Plugin owner before it
returns a candidate.

`TURN-REQ-027`: When an Agent declares more than one Plugin, the Plugin
boundary shall compose Plugin contributions serially in declaration order.

`TURN-REQ-028`: When a Plugin contributes to a Turn, the Plugin boundary shall
give it only its declared Agent projection, its owned prepared input, its
current owned state, and the Turn Directives that it owns.

`TURN-REQ-029`: When a stateful Plugin returns a valid contribution, the Turn
evaluator shall replace only that Plugin's complete owned state entry.

`TURN-REQ-030`: While Plugin composition runs, the Plugin boundary shall not
give a Plugin the complete executable output or another Plugin's contribution.

`TURN-REQ-031`: If Plugin composition fails, then the Turn evaluator shall stop
at the first failure and return no candidate Agent.

`TURN-REQ-032`: When executable output and Plugin contributions are complete,
the Agent boundary shall validate one complete candidate Agent.

`TURN-REQ-033`: When candidate validation succeeds, the Turn evaluator shall
return the candidate Agent, the ordered Directive list, the effective Signal,
and private execution metadata to its caller.

### Errors and private stages

`TURN-REQ-034`: If an application callback raises, throws, exits, or returns an
invalid value, then its owning Jido wrapper shall return the defined seam-12
error for that callback boundary.

`TURN-REQ-035`: If the Turn evaluator detects a broken internal invariant, then
the live Jido runtime shall exit through OTP instead of returning an ordinary
application error.

`TURN-REQ-036`: When Turn evaluation returns an error to a private runtime
caller, the Turn evaluator shall identify one stage from `route`, `prepare`,
`input`, `execute`, `compose`, or `validate`.

### Direct and live boundaries

`TURN-REQ-037`: When `Jido.Agent.cmd/3` evaluates a command, the Agent boundary
shall use the Turn evaluator's candidate-evaluation contract.

`TURN-REQ-038`: When direct evaluation succeeds, `Jido.Agent.cmd/3` shall
return `{:ok, candidate_agent, directives}`.

`TURN-REQ-039`: When direct evaluation returns a candidate, the Agent boundary
shall not commit the candidate or handle its Directives.

`TURN-REQ-040`: When live execution evaluates the same evaluator input and
receives the same executable result as direct execution, the Agent Server shall
use the same candidate assembly and validation contract.

`TURN-REQ-041`: Where live admission, Directive limits, dispatch validation,
timeouts, cancellation, or persistence apply, the Agent Server shall enforce
those policies outside the shared candidate-parity contract.

`TURN-REQ-042`: The Turn evaluator shall own no process, task, timer,
supervisor, persistence operation, state commit, Directive dispatch, or
cancellation operation.

`TURN-REQ-043`: If executable code completes external work before evaluation
fails, then the Turn evaluator shall not report that external work as rolled
back.

## Public contract

The seam adds no required public evaluator module or result struct.
`Jido.Agent.cmd/3` remains the public direct boundary and returns a candidate
Agent and Directives or a defined error. `Jido.Agent.Turn` remains the public
prepared value returned by custom `handle_signal/2` callbacks.

The private evaluation result carries the candidate, ordered Directives,
effective Signal, private execution metadata, and a failure stage when needed.
The exact private module and prepare/resume function names are implementation
details. Private execution output and Plugin accumulators do not enter the
Agent, a checkpoint, a public command result, or a Turn Outcome.

The private stage set describes candidate evaluation only:

| Stage | Meaning |
| --- | --- |
| `route` | Source-Signal selection or custom routing |
| `prepare` | Plugin preparation and effective input |
| `input` | Executable input construction |
| `execute` | One `Jido.Exec` operation |
| `compose` | Result normalization and Plugin contribution |
| `validate` | Final Directive and candidate validation |

Seams 08 and 13 own live control stages and public Outcome stages. They must
define an explicit mapping instead of reusing this set by implication.

## Invariants

- `TURN-INV-001`: One source Signal selects at most one fixed executable for
  one Turn.
- `TURN-INV-002`: Plugin preparation cannot cause a second route lookup.
- `TURN-INV-003`: An executable cannot write Plugin-owned state.
- `TURN-INV-004`: A Plugin cannot write domain state or another Plugin's state.
- `TURN-INV-005`: Direct and live candidate production use one semantic
  boundary.
- `TURN-INV-006`: Evaluation has no commit or post-commit authority.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 05 Plugins | Selection is fixed before preparation; Plugin input and contribution ownership are enforced by the evaluator. |
| 06 Commit and effects | Success supplies one validated candidate and ordered Directive list; no commit has occurred. |
| 08 Agent Server | Live execution can use one candidate contract while it keeps admission, task control, persistence, and dispatch policy. |
| 12 Errors and contracts | Evaluator callback failures and invalid values cross the boundary as defined errors. |
| 13 Observability | Private evaluator stages have a closed set that can map to bounded live observation. |
| 99 Delivery | Route, isolation, parity, and failure requirements have stable acceptance identifiers. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `TURN-DEC-001` | Which Router target wins? | Select the first target returned for the source Signal. | Current multiple-match errors become deterministic selections. |
| `TURN-DEC-002` | How does custom routing fit the order? | Call `handle_signal/2` with the source Signal and keep its valid Turn fixed. | Custom routing stays supported, but Plugin preparation cannot change it. |
| `TURN-DEC-003` | What does direct/live parity cover? | Cover candidate assembly for equal evaluator inputs and executable results. | Live-only policy stays in the Agent Server. |
| `TURN-DEC-004` | Which private stages identify errors? | Use `route`, `prepare`, `input`, `execute`, `compose`, and `validate`. | Server and observation seams can define explicit mappings. |
| `TURN-DEC-005` | Must live evaluation use one task? | No. Let seam 08 choose one task or a private prepare/resume protocol. | OTP structure can change without changing Turn semantics. |
| `TURN-DEC-006` | Does definition revision pin executable code? | No for V3. Use the exact selected executable with the code loaded when `Jido.Exec` runs. | Restore revision does not promise a BEAM code snapshot. |
| `TURN-DEC-007` | Does live Plugin admission belong inside evaluation? | Keep it as live-only preprocessing that cannot change the source Signal or selected executable. | Direct evaluation has no runtime dependency. |
