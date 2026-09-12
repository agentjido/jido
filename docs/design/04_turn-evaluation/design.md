# Turn evaluation design

This document defines the selected Turn evaluation contract. Its review status
is in the main [design index](../README.md).

## Model

One evaluation starts with an Agent instance and an unchanged source Signal.
The sequence is:

```text
Agent A0 + source Signal S0
  -> prepare package inputs from S0
  -> select one fixed Turn from S0
  -> build executable input
  -> call Jido.Exec once
  -> normalize state and Directives
  -> run Jido.Agent.Plugin.Pipeline
  -> validate Agent A1
  -> return A1 and Directives
```

The default route path selects the first target returned by the Signal Router.
Route defaults are merged with source Signal data. Signal data has precedence.
Pure preparation and live admission can reject input. Pure preparation can add
one portable input for each Plugin package. Live admission can add one
transient runtime input for each Plugin package. Neither phase can change the
Agent, source Signal, or caller context.

A custom `handle_signal/2` callback receives the source Signal. A valid Turn
from that callback fixes its executable and input.

Actions and Flows receive package inputs under `context.plugin_inputs`. They
propose the complete candidate state and the complete Directive list. The
Agent Plugin pipeline protects owned fields, validates each Directive once,
and reduces each owned field through `reduce/2` in declaration order.

The evaluator is a value boundary, not a process owner. Direct evaluation can
run it in the caller process. Live evaluation can run it inside a Task owned by
an Agent Server. In both locations, it receives explicit values and returns a
candidate and Directives or an error. It does not identify its caller through
`self/0`, process dictionary values, links, monitors, or task ownership.

## Requirements

### Selection and input

`TURN-REQ-001`: The evaluator shall preserve the received Signal as the source
Signal.

`TURN-REQ-002`: The evaluator shall validate each Agent and Signal one time at
its evaluation trust boundary before executable work starts.

`TURN-REQ-003`: The evaluator shall process Plugin preparation, selection,
input construction, execution, Plugin finalization, and candidate validation
in that order.

`TURN-REQ-004`: An Agent without Plugins shall use the same evaluation path.

`TURN-REQ-005`: Default routing shall use the source Signal.

`TURN-REQ-006`: Default routing shall select the first Router target.

`TURN-REQ-007`: No-route failure shall occur before executable work.

`TURN-REQ-008`: Selection shall keep the executable fixed for the Turn.

`TURN-REQ-009`: Selection shall keep route defaults fixed for the Turn.

`TURN-REQ-010`: Route input shall be a shallow merge in which source Signal
data replaces route defaults.

`TURN-REQ-011`: A custom `handle_signal/2` callback shall receive the source
Signal.

`TURN-REQ-012`: A valid custom Turn shall keep its executable and input fixed.

`TURN-REQ-013`: An invalid custom callback result or fault shall return the
defined callback error before executable work.

`TURN-REQ-014`: Before selection, the evaluator shall call each declared Agent
Plugin `prepare/2` callback in declaration order.

`TURN-REQ-015`: Agent Plugin preparation shall receive the unchanged source
Signal, Agent identity, Agent module, the complete current state, its owned
state, and static options.

`TURN-REQ-016`: Agent Plugin preparation shall return one input owned by its
package or reject evaluation.

`TURN-REQ-017`: The evaluator shall require each pure prepared input to be
portable.

`TURN-REQ-018`: Agent Plugin preparation shall not replace the Agent, source
Signal, caller context, route, or another package's input.

`TURN-REQ-019`: Live Agent Server admission shall return only its own package
runtime input or reject evaluation.

`TURN-REQ-020`: The evaluator shall expose separate `prepared` and `runtime`
slots for each package under the reserved `context.plugin_inputs` key.

### Execution and candidate assembly

`TURN-REQ-021`: The evaluator shall call `Jido.Exec` once for the selected
Action or Flow.

`TURN-REQ-022`: `Jido.Exec` shall receive the exact selected executable.

`TURN-REQ-023`: Only the Action or Flow can propose domain-state changes.

`TURN-REQ-024`: Successful executable output shall contain a complete plain
state map.

`TURN-REQ-025`: The evaluator shall reject executable changes to Plugin-owned
fields.

`TURN-REQ-026`: The evaluator shall validate every built-in or Plugin-owned
Directive before candidate return.

`TURN-REQ-027`: Agent Plugin state reducers shall run serially in declaration
order.

`TURN-REQ-028`: An Agent Plugin reducer shall receive the prior complete state,
the current complete candidate state, its owned value, its pure prepared input,
all validated Directives, and its static options.

`TURN-REQ-029`: An Agent Plugin reducer shall return only its owned field.

`TURN-REQ-030`: An Agent Plugin reducer shall not change the Signal, caller
context, domain state, or another Plugin's state or input.

`TURN-REQ-031`: Plugin finalization shall stop at the first failure and return
no candidate.

`TURN-REQ-032`: The evaluator shall validate the complete proposed state one
time after all Plugin state reductions.

`TURN-REQ-033`: Successful direct evaluation shall return the candidate Agent
and ordered Directive list.

### Boundaries and failures

`TURN-REQ-034`: Application callback faults and invalid results shall cross
their owner wrapper as defined errors.

`TURN-REQ-036`: Private evaluator failures shall identify one stage from
`route`, `prepare`, `input`, `execute`, `compose`, or `validate`.

`TURN-REQ-037`: `Jido.Agent.cmd/3` shall use this candidate contract.

`TURN-REQ-038`: Direct success shall return
`{:ok, candidate_agent, directives}`.

`TURN-REQ-039`: Direct evaluation shall not commit state or handle Directives.

`TURN-REQ-040`: Direct and live evaluation shall use the same finalization
contract for the same executable result.

`TURN-REQ-041`: Live admission, limits, timeouts, persistence, and dispatch
shall stay outside direct evaluation and candidate finalization.

`TURN-REQ-042`: The evaluator shall own no process, timer, persistence,
commit, dispatch, or cancellation operation.

`TURN-REQ-043`: Evaluation failure shall not claim to undo external work that
an executable already completed.

`TURN-REQ-044`: A prepared Turn shall contain the unchanged source Signal.

`TURN-REQ-045`: When an Agent Server runs evaluation inside an owned Task, the
evaluator shall return only a candidate Agent and ordered Directive list or an
error, and shall receive no live commit, relationship, or lifecycle authority.

`TURN-REQ-046`: Whether evaluation runs in a direct caller process or an Agent
Server-owned Task, evaluation order, result meaning, and error meaning shall
not depend on the caller PID or process dictionary.

## Public contract

This seam adds no public evaluator module. `Jido.Agent.cmd/3` and
`Jido.Agent.Turn` are the public contracts. `Jido.Agent.Command` is the live
Agent Server admission envelope and is not part of direct evaluation. The
Runner, prepared Runner data, stage mapping, and Agent Plugin pipeline are
implementation details.

## Invariants

- One source Signal selects at most one executable for one Turn.
- A Plugin cannot change the incoming Signal or caller context.
- Each Plugin can prepare or admit only its package-owned input.
- An executable cannot write Plugin-owned state.
- A Plugin cannot write domain state or another Plugin's state.
- Direct and live candidate production use one finalization contract.
- Evaluation has no commit or post-commit authority.
- Evaluation location does not change evaluation authority or result meaning.
