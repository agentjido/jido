# Turn evaluation alignment

## Status

The one-phase Turn evaluation contract is implemented on branch `v3-spike`.

## Evidence

| Source | Evidence |
| --- | --- |
| `lib/jido/agent/runner.ex` | Direct and live paths share selection and finalization without a direct-path Command. |
| `lib/jido/agent/plugin/pipeline.ex` | One post-execution entry point protects state, validates Directives, and updates owned state. |
| `lib/jido/agent/turn.ex` | A Turn keeps the unchanged source Signal. |
| `test/jido/agent/turn_evaluation_test.exs` | Selection, input, result, and candidate rules pass. |
| `test/jido/plugin/contract_test.exs` | Owned-state and Directive boundaries pass. |
| `test/jido/plugin/ordering_test.exs` | Plugin updates are ordered and fail fast. |
| `test/examples/99_research/99_10_plugin_isolation` | Plugin-owned state update and write protection pass. |

## Current implementation

Direct evaluation calls `Runner.run/3`. Live evaluation uses Runner preparation,
starts asynchronous `Jido.Exec`, and then calls the same Runner finalization.
This split lets the Agent Server own task and timeout policy without duplicating
candidate assembly.

The direct path validates its Agent and Signal at entry. The live path trusts
the admitted Command and validates only values changed during admission. Each
path builds and validates one selected Turn and one complete proposed state.

The source Signal selects the Turn. A live Agent Server Plugin can change the
admitted Command's effective Signal or context. Route input can use that
effective Signal data, but selection does not run again.

## Remaining work

| Gap | Owner | State |
| --- | --- | --- |
| Some higher-level design documents still describe the retired Agent Plugin preparation model. | Design documentation | Open |
| Mixed Plugin package callbacks remain as a separate declaration compatibility path. | Plugin declaration | Open |

## Acceptance

The contract is complete when core and example checks pass, no production API
mentions Agent Plugin preparation, and dependent design documents use or retire
the old requirements explicitly.
