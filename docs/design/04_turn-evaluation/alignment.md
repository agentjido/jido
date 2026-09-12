# Turn evaluation alignment

## Status

The prepared-input Turn evaluation contract is implemented on branch
`v3-spike`. The process-neutral execution refinement in `TURN-REQ-045` and
`TURN-REQ-046` is pending approval and implementation.

## Evidence

| Source | Evidence |
| --- | --- |
| `lib/jido/agent/runner.ex` | Direct and live paths share pure preparation, selection, and finalization without a direct-path Command. |
| `lib/jido/agent/plugin.ex` | Pure preparation reads complete Agent state and returns one portable input for each package. |
| `lib/jido/agent_server/plugin.ex` | Live admission receives a read-only value and returns only its package runtime input. |
| `lib/jido/agent/plugin/pipeline.ex` | One post-execution entry point protects state, validates each Directive once, and reduces owned state. |
| `lib/jido/agent/turn.ex` | A Turn keeps the unchanged source Signal. |
| `test/jido/agent/turn_evaluation_test.exs` | Selection, input, result, and candidate rules pass. |
| `test/jido/plugin/contract_test.exs` | Owned-state and Directive boundaries pass. |
| `test/jido/plugin/preparation_test.exs` | Complete-state reads, reduction, direct and live preparation, rejection, portability, and reserved context pass. |
| `test/jido/plugin/ordering_test.exs` | Plugin admission and reducers are ordered and fail fast. |
| `test/examples/99_research/99_10_plugin_isolation` | Plugin-owned state reduction and write protection pass. |

## Current implementation

Direct evaluation calls `Runner.run/3`. Live evaluation uses Runner preparation,
starts asynchronous `Jido.Exec`, and then calls the same Runner finalization.
This split lets the Agent Server own live admission, task, and timeout policy
without duplicating pure preparation or candidate assembly.

The current split already keeps commit authority out of the Runner. However,
some live preparation and finalization still run in the Agent Server process.
The [Agent Server target design](../08_agent-server/design.md) proposes moving
the complete live evaluation value boundary into one owned Task. That move
must not change evaluator results or give the Task live authority.

The direct path validates its Agent and Signal at entry and runs pure Plugin
preparation. The live path runs the same preparation and then live admission.
Each path builds and validates one selected Turn and one complete proposed
state.

The source Signal selects the Turn and supplies route data. A live Agent Server
Plugin can return only its package runtime input. It cannot change the Signal,
caller context, Agent, pure prepared input, or another package's input.

## Remaining work

| Gap | Owner | State |
| --- | --- | --- |
| Mixed Plugin package callbacks remain as a separate declaration compatibility path. | Plugin declaration | Open |
| The complete live evaluation boundary does not yet run in one owned Task. | Agent Server | Pending design approval |
| Process-neutral evaluation behavior does not yet have focused direct-versus-Task evidence. | Turn evaluation | Missing evidence |

## Acceptance

The contract is complete when core and example checks pass, dependent design
documents describe the narrow prepared-input authority, and direct and
Task-contained evaluation have the same value semantics.
