# Executable Continuation

- **ID:** `02_08_executable_continuation`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 4

## SDK obligation

Dispatch, shared context and continuation budget, terminal output validation, and timeout.

## Acceptance cases

- Flow and Action continuations share context and commit only the terminal result.
- One continuation budget bounds the whole chain without an intermediate commit.
- The terminal Flow validates its output after prior executables finish.
- An execution timeout ends the active chain and stops its worker.

## Implementation and evidence

- [Source](../../../../examples/02_workflow/02_08_executable_continuation/executable_continuation.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_08_executable_continuation/executable_continuation_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

New SDK fixture. See the [research archive](../../archive/workflow/README.md).
