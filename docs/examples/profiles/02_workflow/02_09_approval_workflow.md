# Approval Workflow

- **ID:** `02_09_approval_workflow`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 5

## SDK obligation

Separate approval Turns, post-commit Plugin dispatch, correlation, duplicates, and provider failure.

## Acceptance cases

- Approval commits before a process-free Plugin books and a later Signal completes.
- A valid stale revision fails selection and cancelled work cannot be approved.
- Queued duplicate approval creates only one provider attempt.
- Stale and duplicate result Signals cannot replace a terminal booking.
- Provider failure enters through a separate result Turn.

## Implementation and evidence

- [Source](../../../../lib/examples/02_workflow/02_09_approval_workflow/approval_workflow.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_09_approval_workflow/approval_workflow_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Flight Booking. See the [research archive](../../archive/workflow/README.md).
